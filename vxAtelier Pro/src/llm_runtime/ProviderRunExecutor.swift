import Foundation
import SwiftData

/// Executes provider adapters and accumulates normalized run output.
struct ProviderRunExecutor {
    let registry: LLMProviderRegistry

    /// Creates an executor with an injectable provider registry.
    init(registry: LLMProviderRegistry = .shared) {
        self.registry = registry
    }

    /// Performs one provider run, retrying once for retryable failures when requested.
    @MainActor
    func performRun(
        request: LLMRequest,
        providerConfiguration: LLMProviderConfiguration,
        draftSink: any ConversationDraftSink,
        conversationID: PersistentIdentifier,
        toolExecutor: LLMToolExecutionHandler? = nil,
        retryPolicy: LLMGenerationOptions.RetryPolicy
    ) async throws -> ProviderRunResult {
        do {
            return try await collectRun(
                request: request,
                providerConfiguration: providerConfiguration,
                draftSink: draftSink,
                conversationID: conversationID,
                toolExecutor: toolExecutor
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
                conversationID: conversationID,
                toolExecutor: toolExecutor
            )
        }
    }

    /// Extracts response metadata carried by a provider-domain error.
    func responseMetadata(from error: Error) -> LLMResponseMetadata? {
        guard case .provider(_, _, let metadata) = error as? LLMProviderError else {
            return nil
        }
        return metadata
    }

    /// Collects adapter stream events into persisted-result data and transient draft updates.
    @MainActor
    private func collectRun(
        request: LLMRequest,
        providerConfiguration: LLMProviderConfiguration,
        draftSink: any ConversationDraftSink,
        conversationID: PersistentIdentifier,
        toolExecutor: LLMToolExecutionHandler?
    ) async throws -> ProviderRunResult {
        guard providerConfiguration.providerID == request.providerID else {
            throw LLMProviderError.invalidConfiguration(
                "Provider configuration \(providerConfiguration.providerID.rawValue) does not match request provider \(request.providerID.rawValue)."
            )
        }
        let adapter = registry.adapter(for: request.adapterID, providerID: request.providerID)
        var result = ProviderRunResult()

        for try await event in adapter.stream(request, configuration: providerConfiguration, toolExecutor: toolExecutor) {
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
            case .toolOutputCompleted(let output):
                upsert(output, into: &result.toolOutputs)
            case .usage(let usage):
                result.usage = usage
            case .runCompleted(let responseID, let modelID):
                result.requestID = result.requestID ?? responseID
                result.actualModelID = modelID
            }
        }

        return result
    }

    /// Inserts or replaces a streamed tool call using provider order and identifiers.
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

    /// Inserts or replaces a streamed native tool output using provider order and identifiers.
    private func upsert(_ output: LLMToolOutput, into outputs: inout [LLMToolOutput]) {
        if let existingIndex = outputs.firstIndex(where: { existing in
            existing.index == output.index || existing.id == output.id || existing.callID == output.callID
        }) {
            outputs[existingIndex] = output
        } else {
            outputs.append(output)
            outputs.sort { $0.index < $1.index }
        }
    }

    /// Returns true for transient network and provider status failures.
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

    /// Honors a bounded Retry-After value before retrying a provider request.
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
