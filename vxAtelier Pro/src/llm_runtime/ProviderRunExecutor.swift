import Foundation
import SwiftData

struct ProviderRunExecutor {
    let registry: LLMProviderRegistry

    init(registry: LLMProviderRegistry = .shared) {
        self.registry = registry
    }

    @MainActor
    func performRun(
        request: LLMRequest,
        providerConfiguration: LLMProviderConfiguration,
        draftSink: any ConversationDraftSink,
        conversationID: PersistentIdentifier,
        retryPolicy: LLMGenerationOptions.RetryPolicy
    ) async throws -> ProviderRunResult {
        do {
            return try await collectRun(
                request: request,
                providerConfiguration: providerConfiguration,
                draftSink: draftSink,
                conversationID: conversationID
            )
        } catch {
            guard retryPolicy == .oneRetryBeforeTools, isRetryable(error) else { throw error }
            try await sleepBeforeRetry(for: error)
            draftSink.reset(conversationID: conversationID)
            draftSink.start(conversationID: conversationID)
            return try await collectRun(
                request: request,
                providerConfiguration: providerConfiguration,
                draftSink: draftSink,
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
        providerConfiguration: LLMProviderConfiguration,
        draftSink: any ConversationDraftSink,
        conversationID: PersistentIdentifier
    ) async throws -> ProviderRunResult {
        guard providerConfiguration.providerID == request.providerID else {
            throw LLMProviderError.invalidConfiguration(
                "Provider configuration \(providerConfiguration.providerID.rawValue) does not match request provider \(request.providerID.rawValue)."
            )
        }
        let adapter = registry.adapter(for: request.providerID)
        var result = ProviderRunResult()

        for try await event in adapter.stream(request, configuration: providerConfiguration) {
            switch event {
            case .runStarted(let requestID):
                result.requestID = result.requestID ?? requestID
            case .responseMetadata(let metadata):
                result.metadata = metadata
                result.requestID = metadata.requestID ?? result.requestID
            case .textDelta(let delta):
                result.text += delta
                draftSink.appendContent(delta, conversationID: conversationID)
            case .reasoningDelta(let delta):
                result.reasoning += delta
            case .toolCallDelta(let call):
                upsert(call, into: &result.toolCalls)
                draftSink.updateToolCalls([call], conversationID: conversationID)
            case .toolCallCompleted(let call):
                upsert(call, into: &result.toolCalls)
                draftSink.updateToolCalls(result.toolCalls, conversationID: conversationID)
            case .usage(let usage):
                result.usage = usage
            case .runCompleted(let responseID, let modelID):
                result.requestID = result.requestID ?? responseID
                result.actualModelID = modelID
            }
        }

        return result
    }

    private func upsert(_ call: LLMToolCall, into calls: inout [LLMToolCall]) {
        if let existingIndex = calls.firstIndex(where: { existing in
            existing.index == call.index || existing.id == call.id || (call.callID != nil && existing.callID == call.callID)
        }) {
            calls[existingIndex] = call
        } else {
            calls.append(call)
            calls.sort { $0.index < $1.index }
        }
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
