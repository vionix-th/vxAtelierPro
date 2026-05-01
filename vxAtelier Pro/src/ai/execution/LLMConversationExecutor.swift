import Foundation
import SwiftData

@MainActor
final class LLMConversationExecutor {
    static let shared = LLMConversationExecutor()

    private let requestBuilder: LLMConversationRequestBuilder
    private let runCollector: LLMRunCollector
    private let toolCoordinator: LLMToolExecutionCoordinator
    private let persistence: LLMPersistenceCoordinator

    init(
        requestBuilder: LLMConversationRequestBuilder = LLMConversationRequestBuilder(),
        runCollector: LLMRunCollector = LLMRunCollector(),
        persistence: LLMPersistenceCoordinator = LLMPersistenceCoordinator()
    ) {
        self.requestBuilder = requestBuilder
        self.runCollector = runCollector
        self.persistence = persistence
        self.toolCoordinator = LLMToolExecutionCoordinator(persistence: persistence)
    }

    func complete(
        conversation: ConversationItem,
        message: String,
        draftStore: ConversationDraftStore
    ) async throws {
        guard let apiConfig = conversation.options.apiConfiguration else {
            throw LLMProviderError.invalidConfiguration("No API configuration available.")
        }

        let turn = addUserMessage(message, to: conversation)
        try persistence.save(conversation)
        draftStore.start(conversationID: conversation.id)

        do {
            try await runUntilStable(
                conversation: conversation,
                turn: turn,
                apiConfig: apiConfig,
                draftStore: draftStore
            )
            draftStore.complete(conversationID: conversation.id)
            conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: true)
            try persistence.save(conversation)
        } catch {
            draftStore.fail(error, conversationID: conversation.id)
            if turn.responseRuns.isEmpty {
                try persistence.removeTurn(turn, from: conversation)
                conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
                try persistence.save(conversation)
            }
            throw error
        }
    }

    private func runUntilStable(
        conversation: ConversationItem,
        turn: ConversationTurn,
        apiConfig: APIConfigurationItem,
        draftStore: ConversationDraftStore,
        depth: Int = 0
    ) async throws {
        guard depth < 10 else {
            throw LLMProviderError.unsupportedCapability("Max tool recursion depth exceeded.")
        }

        let request = try requestBuilder.makeRequest(conversation: conversation, apiConfig: apiConfig)
        let run = ResponseRunItem(
            providerID: request.providerID,
            endpointFamily: request.endpointFamily,
            requestedModelID: request.modelID,
            status: .pending,
            turn: turn
        )
        turn.responseRuns.append(run)
        try run.transition(to: .streaming)
        try persistence.save(conversation)

        let response: LLMRunAccumulator
        do {
            response = try await runCollector.performRun(
                request: request,
                apiConfig: apiConfig,
                draftStore: draftStore,
                conversationID: conversation.id,
                retryPolicy: request.options.retryPolicy
            )
        } catch {
            let normalizedError = normalizedRunError(error)
            if let metadata = runCollector.responseMetadata(from: error) {
                run.applyMetadata(metadata)
            }
            try? run.transition(to: isCancellation(normalizedError) ? .cancelled : .failed)
            run.errorMessage = normalizedError.localizedDescription
            run.completedAt = Date()
            try persistence.save(conversation)
            throw normalizedError
        }

        try run.transition(to: response.toolCalls.isEmpty ? .completed : .awaitingTools)
        run.actualModelID = response.actualModelID
        run.requestID = response.requestID
        run.applyUsage(response.usage)
        if let metadata = response.metadata {
            run.applyMetadata(metadata)
        }
        run.completedAt = response.toolCalls.isEmpty ? Date() : nil
        try persistence.save(conversation)

        if response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && response.toolCalls.isEmpty {
            return
        }

        let assistantMessage = appendAssistantMessage(
            response.text,
            toolCalls: response.toolCalls,
            to: turn
        )
        try persistence.save(conversation)

        guard !assistantMessage.toolCallItems.isEmpty else {
            run.completedAt = Date()
            try persistence.save(conversation)
            return
        }

        do {
            try await toolCoordinator.execute(
                assistantMessage.toolCallItems.sorted { $0.index < $1.index },
                conversation: conversation,
                turn: turn
            )
        } catch {
            let normalizedError = normalizedRunError(error)
            try? run.transition(to: isCancellation(normalizedError) ? .cancelled : .failed)
            run.errorMessage = normalizedError.localizedDescription
            run.completedAt = Date()
            try persistence.save(conversation)
            throw normalizedError
        }
        try run.transition(to: .completed)
        run.completedAt = Date()
        try persistence.save(conversation)

        draftStore.reset(conversationID: conversation.id)
        draftStore.start(conversationID: conversation.id)
        try await runUntilStable(
            conversation: conversation,
            turn: turn,
            apiConfig: apiConfig,
            draftStore: draftStore,
            depth: depth + 1
        )
    }

    private func addUserMessage(_ message: String, to conversation: ConversationItem) -> ConversationTurn {
        let userMsg = MessageItem(
            role: "user",
            contentParts: [MessageContentPartItem(index: 0, kind: .text, text: message)],
            timestamp: Date()
        )
        let nextSequence = (conversation.turns.map(\.sequenceNumber).max() ?? -1) + 1
        let turn = ConversationTurn(sequenceNumber: nextSequence, timestamp: userMsg.timestamp, userMessage: userMsg, conversation: conversation)
        conversation.turns.append(turn)
        conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
        return turn
    }

    private func appendAssistantMessage(
        _ text: String,
        toolCalls: [LLMToolCall],
        to turn: ConversationTurn
    ) -> MessageItem {
        let message = MessageItem(
            role: "assistant",
            contentParts: [MessageContentPartItem(index: 0, kind: .text, text: text)],
            timestamp: Date()
        )
        message.toolCallItems = toolCalls.sorted { $0.index < $1.index }.map { call in
            ToolCallItem(
                callID: call.id,
                providerCallID: call.callID,
                index: call.index,
                name: call.name,
                argumentsJSON: call.argumentsJSON,
                status: .readyToExecute,
                assistantMessage: message
            )
        }
        turn.events.append(TurnEvent(type: .assistant, timestamp: message.timestamp, message: message, turn: turn))
        return message
    }

    private func isCancellation(_ error: Error) -> Bool {
        if case .cancelled = error as? LLMProviderError {
            return true
        }
        return error is CancellationError
    }

    private func normalizedRunError(_ error: Error) -> Error {
        isCancellation(error) ? LLMProviderError.cancelled : error
    }
}
