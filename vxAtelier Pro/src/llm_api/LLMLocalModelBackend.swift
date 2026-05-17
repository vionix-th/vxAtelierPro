import Foundation

/// Availability surface for a local on-device model backend.
enum LLMLocalModelAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .available:
            return "On-device model available"
        case .unavailable(let message):
            return message
        }
    }
}

/// Local-model backend seam used by non-HTTP providers.
protocol LLMLocalModelBackend {
    var profile: LLMProviderProfile { get }

    func availability() -> LLMLocalModelAvailability
    func statusText() -> String
    func modelCandidates(configuration: LLMProviderConfiguration) -> [LLMModelDescriptor]
    func stream(
        request: LLMRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

extension LLMLocalModelBackend {
    func statusText() -> String {
        availability().statusText
    }
}
