import Foundation

/// Controls whether a stream may complete by EOF or needs an explicit provider event.
struct LLMSSECompletionPolicy {
    var requiresExplicitCompletionEvent: Bool
    var didComplete: ([String: JSONValue]) -> Bool

    static let synthesizeOnStreamEnd = LLMSSECompletionPolicy(
        requiresExplicitCompletionEvent: false,
        didComplete: { _ in false }
    )

    /// Requires the stream to emit an event that satisfies the completion detector.
    static func requireExplicitEvent(
        _ detector: @escaping ([String: JSONValue]) -> Bool
    ) -> LLMSSECompletionPolicy {
        LLMSSECompletionPolicy(
            requiresExplicitCompletionEvent: true,
            didComplete: detector
        )
    }
}

/// Provider adapters translate provider wire formats into the stable LLM domain.
///
/// Contract:
/// - Emit provider-neutral `LLMGenerationEvent` values for streamed and non-streamed requests.
/// - Emit `.responseMetadata` when HTTP response metadata is available.
/// - Emit `.generationCompleted` exactly once for complete provider responses, or throw if the provider stream ends before a required completion event.
/// - Emit tool-call deltas and completed calls using provider order indexes so `LLMToolCallAssembler` can merge fragments deterministically.
/// - Return model candidates using provider metadata and bundled model defaults; throw for unsupported model listing instead of fabricating models.
typealias LLMToolExecutionHandler = @MainActor @Sendable (_ toolName: String, _ argumentsJSON: String) async throws -> String

protocol LLMProviderAdapter {
    var profile: LLMProviderProfile { get }

    /// Sends a request and emits normalized events regardless of provider wire format.
    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error>

    /// Fetches provider model metadata and maps it into normalized candidates.
    func fetchModelMetadata(configuration: LLMProviderConfiguration) async throws -> [LLMModelMetadata]
}

/// Adapter used for configured providers that are intentionally unavailable.
struct DisabledLLMProviderAdapter: LLMProviderAdapter {
    let profile: LLMProviderProfile
    let message: String

    /// Fails immediately with the configured unavailability reason.
    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMProviderError.authUnavailable(message))
        }
    }

    /// Fails immediately because this provider cannot list models in the current build.
    func fetchModelMetadata(configuration: LLMProviderConfiguration) async throws -> [LLMModelMetadata] {
        throw LLMProviderError.authUnavailable(message)
    }
}
