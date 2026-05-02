import Foundation

struct LLMStreamCompletionPolicy {
    var requiresExplicitCompletionEvent: Bool
    var didComplete: ([String: JSONValue]) -> Bool

    static let synthesizeOnStreamEnd = LLMStreamCompletionPolicy(
        requiresExplicitCompletionEvent: false,
        didComplete: { _ in false }
    )

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

    func stream(_ request: LLMRequest, configuration: APIConfigurationItem) -> AsyncThrowingStream<LLMStreamEvent, Error>
    func fetchModels(configuration: APIConfigurationItem) async throws -> [LLMModelDescriptor]
}

struct DisabledLLMProviderAdapter: LLMProviderAdapter {
    let profile: LLMProviderProfile
    let message: String

    func stream(_ request: LLMRequest, configuration: APIConfigurationItem) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMProviderError.authUnavailable(message))
        }
    }

    func fetchModels(configuration: APIConfigurationItem) async throws -> [LLMModelDescriptor] {
        throw LLMProviderError.authUnavailable(message)
    }
}
