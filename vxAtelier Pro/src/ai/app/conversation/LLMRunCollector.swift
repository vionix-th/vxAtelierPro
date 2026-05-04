import Foundation
import SwiftData

struct LLMRunAccumulator {
    var text: String = ""
    var reasoning: String = ""
    var toolCalls: [LLMToolCall] = []
    var usage: LLMUsage = LLMUsage()
    var metadata: LLMResponseMetadata?
    var requestID: String?
    var actualModelID: String?
}

struct LLMRunCollector {
    let registry: LLMProviderRegistry

    init(registry: LLMProviderRegistry = .shared) {
        self.registry = registry
    }

    @MainActor
    func performRun(
        request: LLMRequest,
        apiConfig: APIConfigurationItem,
        draftStore: ConversationDraftStore,
        conversationID: PersistentIdentifier,
        retryPolicy: LLMGenerationOptions.RetryPolicy
    ) async throws -> LLMRunAccumulator {
        do {
            return try await collectRun(
                request: request,
                apiConfig: apiConfig,
                draftStore: draftStore,
                conversationID: conversationID
            )
        } catch {
            guard retryPolicy == .oneRetryBeforeTools, isRetryable(error) else { throw error }
            try await sleepBeforeRetry(for: error)
            draftStore.reset(conversationID: conversationID)
            draftStore.start(conversationID: conversationID)
            return try await collectRun(
                request: request,
                apiConfig: apiConfig,
                draftStore: draftStore,
                conversationID: conversationID
            )
        }
    }

    func responseMetadata(from error: Error) -> LLMResponseMetadata? {
        guard case .provider(_, _, let metadata) = error as? LLMProviderError else {
            return nil
        }
        return metadata
    }

    @MainActor
    private func collectRun(
        request: LLMRequest,
        apiConfig: APIConfigurationItem,
        draftStore: ConversationDraftStore,
        conversationID: PersistentIdentifier
    ) async throws -> LLMRunAccumulator {
        let adapter = registry.adapter(for: request.providerID)
        let providerConfiguration = apiConfig.llmProviderConfiguration(
            profile: registry.profile(for: request.providerID)
        )
        var accumulator = LLMRunAccumulator()
        var assembler = LLMToolCallAssembler()

        for try await event in adapter.stream(request, configuration: providerConfiguration) {
            switch event {
            case .runStarted(let requestID):
                accumulator.requestID = accumulator.requestID ?? requestID
            case .responseMetadata(let metadata):
                accumulator.metadata = metadata
                accumulator.requestID = metadata.requestID ?? accumulator.requestID
            case .textDelta(let delta):
                accumulator.text += delta
                draftStore.appendContent(delta, conversationID: conversationID)
            case .reasoningDelta(let delta):
                accumulator.reasoning += delta
            case .toolCallDelta(let call):
                let merged = assembler.merge(call)
                draftStore.updateToolCalls([merged], conversationID: conversationID)
            case .toolCallCompleted(let call):
                _ = assembler.merge(call)
                accumulator.toolCalls = assembler.assembled
                draftStore.updateToolCalls(accumulator.toolCalls, conversationID: conversationID)
            case .usage(let usage):
                accumulator.usage = usage
            case .runCompleted(let responseID, let modelID):
                accumulator.requestID = accumulator.requestID ?? responseID
                accumulator.actualModelID = modelID
            }
        }

        if accumulator.toolCalls.isEmpty {
            accumulator.toolCalls = assembler.assembled
        }
        return accumulator
    }

    private func isRetryable(_ error: Error) -> Bool {
        guard let providerError = error as? LLMProviderError else { return false }
        switch providerError {
        case .network:
            return true
        case .provider(let statusCode, _, _):
            return statusCode == 408 || statusCode == 409 || statusCode == 425 || statusCode == 429 || (500...599).contains(statusCode)
        case .invalidConfiguration, .invalidURL, .authUnavailable, .unsupportedCapability, .unsupportedParameter, .decoding, .cancelled:
            return false
        }
    }

    private func sleepBeforeRetry(for error: Error) async throws {
        let fallbackNanoseconds: UInt64 = 100_000_000
        guard let retryAfter = responseMetadata(from: error)?.retryAfter,
              let seconds = Double(retryAfter) else {
            try await Task.sleep(nanoseconds: fallbackNanoseconds)
            return
        }
        let cappedSeconds = min(max(seconds, 0), 1)
        try await Task.sleep(nanoseconds: UInt64(cappedSeconds * 1_000_000_000))
    }
}
