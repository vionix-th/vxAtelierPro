import Foundation

/// Stable identifier for a supported LLM provider profile.
enum LLMProviderID: String, Codable, CaseIterable, Identifiable {
    case openAIPlatform
    case openAIChatGPTSubscription
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
        case .openAIChatGPTSubscription: return "ChatGPT Subscription"
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

    /// Exposes the raw adapter key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing adapter name for settings and diagnostics.
    var displayName: String {
        switch self {
        case .openAIResponses: return "OpenAI Responses"
        case .openAIChatCompletions: return "OpenAI Chat Completions"
        case .openAICompatibleChatCompletions: return "OpenAI-Compatible Chat Completions"
        case .anthropicMessages: return "Anthropic Messages"
        }
    }
}

/// Authentication scheme required by a provider profile or override.
enum LLMAuthKind: String, Codable, CaseIterable {
    case none
    case bearerToken
    case xAPIKey
    case customHeaders
    case chatGPTOAuth
    case chatGPTDeviceCode
    case chatGPTCodexToken
}

/// Static provider transport metadata used for configuration and adapter selection.
struct LLMProviderProfile: Codable, Identifiable, Equatable {
    var id: LLMProviderID
    var name: String
    var defaultBaseURL: String
    var authKind: LLMAuthKind
    var defaultAdapterID: LLMAdapterID
    var supportedAdapterIDs: [LLMAdapterID]
    var isEnabled: Bool
}
