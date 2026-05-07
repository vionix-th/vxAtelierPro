import Foundation

/// Controls whether a stream may complete by EOF or needs an explicit provider event.
struct LLMStreamCompletionPolicy {
    var requiresExplicitCompletionEvent: Bool
    var didComplete: ([String: JSONValue]) -> Bool

    static let synthesizeOnStreamEnd = LLMStreamCompletionPolicy(
        requiresExplicitCompletionEvent: false,
        didComplete: { _ in false }
    )

    /// Requires the stream to emit an event that satisfies the completion detector.
    static func requireExplicitEvent(
        _ detector: @escaping ([String: JSONValue]) -> Bool
    ) -> LLMStreamCompletionPolicy {
        LLMStreamCompletionPolicy(
            requiresExplicitCompletionEvent: true,
            didComplete: detector
        )
    }
}

/// Provider adapters translate provider wire formats into the stable LLM domain.
///
/// Contract:
/// - Emit provider-neutral `LLMStreamEvent` values for streamed and non-streamed requests.
/// - Emit `.responseMetadata` when HTTP response metadata is available.
/// - Emit `.runCompleted` exactly once for complete provider responses, or throw if the provider stream ends before a required completion event.
/// - Emit tool-call deltas and completed calls using provider order indexes so `LLMToolCallAssembler` can merge fragments deterministically.
/// - Return model descriptors using provider/profile capabilities; throw for unsupported model listing instead of fabricating models.
protocol LLMProviderAdapter {
    var profile: LLMProviderProfile { get }

    /// Sends a request and emits normalized events regardless of provider wire format.
    func stream(_ request: LLMRequest, configuration: LLMProviderConfiguration) -> AsyncThrowingStream<LLMStreamEvent, Error>

    /// Fetches provider model metadata and maps it into normalized descriptors.
    func fetchModels(configuration: LLMProviderConfiguration) async throws -> [LLMModelDescriptor]
}

/// Adapter used for configured providers that are intentionally unavailable.
struct DisabledLLMProviderAdapter: LLMProviderAdapter {
    let profile: LLMProviderProfile
    let message: String

    /// Fails immediately with the configured unavailability reason.
    func stream(_ request: LLMRequest, configuration: LLMProviderConfiguration) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMProviderError.authUnavailable(message))
        }
    }

    /// Fails immediately because this provider cannot list models in the current build.
    func fetchModels(configuration: LLMProviderConfiguration) async throws -> [LLMModelDescriptor] {
        throw LLMProviderError.authUnavailable(message)
    }
}
