import Foundation

/// High-level transport class used by a provider profile.
enum LLMProviderTransportKind: String, Codable, CaseIterable {
    case remoteHTTP
    case localSystem
    case localFile
}

/// Stable identifier for a supported LLM provider profile.
enum LLMProviderID: String, Codable, CaseIterable, Identifiable {
    case openAIPlatform
    case openAICodexChatGPTSubscription
    case appleIntelligence
    case openRouter
    case lmStudio
    case ollama
    case xAI
    case deepSeek
    case anthropic
    case customOpenAICompatible

    /// Exposes the raw provider key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing provider name for settings and diagnostics.
    var displayName: String {
        switch self {
        case .openAIPlatform: return "OpenAI Platform"
        case .openAICodexChatGPTSubscription: return "Codex ChatGPT Subscription"
        case .appleIntelligence: return "Apple Intelligence"
        case .openRouter: return "OpenRouter"
        case .lmStudio: return "LM Studio"
        case .ollama: return "Ollama"
        case .xAI: return "xAI"
        case .deepSeek: return "DeepSeek"
        case .anthropic: return "Anthropic"
        case .customOpenAICompatible: return "Custom OpenAI Compatible"
        }
    }
}

/// Stable identifier for a generation adapter wire contract.
enum LLMAdapterID: String, Codable, CaseIterable, Identifiable {
    case openAIResponses
    case openAIChatCompletions
    case openAICompatibleChatCompletions
    case anthropicMessages
    case foundationModels

    /// Exposes the raw adapter key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing adapter name for settings and diagnostics.
    var displayName: String {
        switch self {
        case .openAIResponses: return "OpenAI Responses"
        case .openAIChatCompletions: return "OpenAI Chat Completions"
        case .openAICompatibleChatCompletions: return "OpenAI-Compatible Chat Completions"
        case .anthropicMessages: return "Anthropic Messages"
        case .foundationModels: return "Foundation Models"
        }
    }
}

/// Authentication scheme required by a provider profile or override.
enum LLMAuthKind: String, Codable, CaseIterable {
    case none
    case bearerToken
    case xAPIKey
    case customHeaders
    case codexChatGPTOAuth
    case codexChatGPTDeviceCode
}

/// Static provider transport metadata used for configuration and adapter selection.
struct LLMProviderProfile: Codable, Identifiable, Equatable {
    var id: LLMProviderID
    var name: String
    var transportKind: LLMProviderTransportKind
    var defaultBaseURL: String
    var authKind: LLMAuthKind
    var defaultAdapterID: LLMAdapterID
    var supportedAdapterIDs: [LLMAdapterID]
    var isEnabled: Bool

    var requiresBaseURL: Bool {
        transportKind == .remoteHTTP
    }

    var requiresCredential: Bool {
        switch transportKind {
        case .remoteHTTP:
            return authKind != .none
        case .localSystem, .localFile:
            return false
        }
    }

    var supportsRemoteModelListing: Bool {
        switch transportKind {
        case .remoteHTTP:
            return true
        case .localSystem, .localFile:
            return false
        }
    }

    var supportsSessionState: Bool {
        switch transportKind {
        case .remoteHTTP:
            return false
        case .localSystem, .localFile:
            return true
        }
    }
}
