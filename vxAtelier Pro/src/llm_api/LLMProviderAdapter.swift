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
/// Responsibilities:
/// - Emit provider-neutral `LLMGenerationEvent` values for streamed and non-streamed requests.
/// - Emit `.responseMetadata` when HTTP response metadata is available.
/// - Emit `.generationCompleted` exactly once for complete provider responses, or throw if the provider stream ends before a required completion event.
/// - Emit tool-call deltas and completed calls using provider order indexes so `LLMToolCallAssembler` can merge fragments deterministically.
/// - Return raw provider model metadata without catalog enrichment; throw when model listing is unavailable unless the provider owns an explicit static inventory.
typealias LLMToolExecutionHandler = @MainActor @Sendable (_ toolName: String, _ argumentsJSON: String) async throws -> String

protocol LLMProviderAdapter {
    var profile: LLMProviderProfile { get }

    /// Sends a request and emits normalized events regardless of provider wire format.
    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error>

    /// Fetches raw provider model metadata.
    func fetchModelMetadata(configuration: LLMProviderConfiguration) async throws -> [LLMProviderModelMetadata]
}
