import Foundation

/// Coordinates a full conversation completion, including provider/tool loops and persistence.
@MainActor
final class ConversationCompletionUseCase {
    static let shared = ConversationCompletionUseCase()

    private let contextResolver: ConversationRunContextResolver
    private let requestFactory: LLMRequestFactory
    private let providerRunExecutor: ProviderRunExecutor
    private let toolBatchExecutor: ToolBatchExecutor
    private let runStore: ConversationRunStore
    private let maxToolDepth: Int

    /// Creates the completion coordinator with injectable collaborators for orchestration tests.
    init(
        contextResolver: ConversationRunContextResolver? = nil,
        requestFactory: LLMRequestFactory = LLMRequestFactory(),
        providerRunExecutor: ProviderRunExecutor = ProviderRunExecutor(),
        toolBatchExecutor: ToolBatchExecutor? = nil,
        runStore: ConversationRunStore = ConversationRunStore(),
        registry: LLMProviderRegistry = .shared,
        toolCatalog: LLMToolCatalog = LLMToolRegistry.shared,
        maxToolDepth: Int = 10
    ) {
        self.contextResolver = contextResolver ?? ConversationRunContextResolver(
            registry: registry,
            toolCatalog: toolCatalog
        )
        self.requestFactory = requestFactory
        self.providerRunExecutor = providerRunExecutor
        self.toolBatchExecutor = toolBatchExecutor ?? ToolBatchExecutor(toolCatalog: toolCatalog)
        self.runStore = runStore
        self.maxToolDepth = maxToolDepth
    }

    /// Appends a user message and runs the conversation until no tool calls remain.
    func complete(
        conversation: ConversationItem,
        message: String,
        draftStore: ConversationDraftStore
    ) async throws {
        guard let apiConfig = conversation.options.apiConfiguration else {
            throw LLMProviderError.invalidConfiguration("No API configuration available.")
        }

        let turn = try runStore.startTurn(message: message, in: conversation)
        let draftSink = ConversationDraftStoreSink(draftStore: draftStore)
        draftSink.start(conversationID: conversation.id)

        do {
            try await runUntilStable(
                conversation: conversation,
                turn: turn,
                apiConfig: apiConfig,
                draftSink: draftSink
            )
            draftSink.complete(conversationID: conversation.id)
            try runStore.finishConversation(conversation)
        } catch {
            let normalizedError = ConversationRunError.normalized(error)
            draftSink.fail(normalizedError, conversationID: conversation.id)
            if turn.responseRuns.isEmpty {
                try runStore.rollbackTurn(turn, from: conversation)
            }
            throw normalizedError
        }
    }

    /// Repeats provider calls and tool execution until the assistant response is stable.
    private func runUntilStable(
        conversation: ConversationItem,
        turn: ConversationTurn,
        apiConfig: APIConfigurationItem,
        draftSink: any ConversationDraftSink
    ) async throws {
        for _ in 0..<maxToolDepth {
            let context = try contextResolver.resolve(conversation: conversation, apiConfig: apiConfig)
            let request = try requestFactory.makeRequest(from: context)
            let run = try runStore.createResponseRun(for: request, turn: turn, conversation: conversation)

            let result: ProviderRunResult
            do {
                result = try await providerRunExecutor.performRun(
                    request: request,
                    providerConfiguration: context.providerConfiguration,
                    draftSink: draftSink,
                    conversationID: context.conversationID,
                    retryPolicy: request.options.retryPolicy
                )
            } catch {
                let normalizedError = try runStore.markRunFailed(
                    run,
                    error: error,
                    metadata: providerRunExecutor.responseMetadata(from: error),
                    conversation: conversation
                )
                throw normalizedError
            }

            guard let assistantMessage = try runStore.applyProviderResult(
                result,
                to: run,
                turn: turn,
                conversation: conversation
            ) else {
                return
            }

            let toolCalls = assistantMessage.toolCallItems.sorted { $0.index < $1.index }
            guard !toolCalls.isEmpty else {
                return
            }

            do {
                try await executeToolCalls(toolCalls, conversation: conversation, turn: turn)
            } catch {
                let normalizedError = try runStore.markRunFailed(run, error: error, conversation: conversation)
                throw normalizedError
            }

            try runStore.completeRunAfterTools(run, conversation: conversation)
            draftSink.reset(conversationID: conversation.id)
            draftSink.start(conversationID: conversation.id)
        }

        throw LLMProviderError.unsupportedCapability("Max tool recursion depth exceeded.")
    }

    /// Executes tool calls sequentially so persisted tool results preserve provider order.
    private func executeToolCalls(
        _ toolCalls: [ToolCallItem],
        conversation: ConversationItem,
        turn: ConversationTurn
    ) async throws {
        for toolCall in toolCalls {
            try runStore.markToolExecuting(toolCall, conversation: conversation)
            do {
                let output = try await toolBatchExecutor.execute(
                    toolCall,
                    conversation: conversation,
                    turn: turn
                )
                try runStore.completeToolCall(
                    toolCall,
                    output: output,
                    turn: turn,
                    conversation: conversation
                )
            } catch {
                if ConversationRunError.isCancellation(error) {
                    try runStore.cancelToolCall(toolCall, conversation: conversation)
                    throw LLMProviderError.cancelled
                }
                try runStore.failToolCall(toolCall, error: error, conversation: conversation)
                throw error
            }
        }
    }
}
