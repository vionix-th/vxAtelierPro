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
    case openCodeZen
    case appleIntelligence
    case openRouter
    case lmStudio
    case ollama
    case xAI
    case deepSeek
    case anthropic
    case custom

    /// Exposes the raw provider key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing provider name for settings and diagnostics.
    var displayName: String {
        switch self {
        case .openAIPlatform: return "OpenAI Platform"
        case .openAICodexChatGPTSubscription: return "Codex ChatGPT Subscription"
        case .openCodeZen: return "OpenCode Zen"
        case .appleIntelligence: return "Apple Intelligence"
        case .openRouter: return "OpenRouter"
        case .lmStudio: return "LM Studio"
        case .ollama: return "Ollama"
        case .xAI: return "xAI"
        case .deepSeek: return "DeepSeek"
        case .anthropic: return "Anthropic"
        case .custom: return "Custom"
        }
    }
}

/// Stable identifier for a generation adapter wire contract.
enum LLMAdapterID: String, Codable, CaseIterable, Identifiable {
    case openAIResponses
    case openAIChatCompletions
    case openAIChatCompletionsLegacy
    case openRouterChatCompletions
    case anthropicMessages
    case foundationModels

    /// Exposes the raw adapter key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing adapter name for settings and diagnostics.
    var displayName: String {
        switch self {
        case .openAIResponses: return "OpenAI Responses"
        case .openAIChatCompletions: return "OpenAI Chat Completions"
        case .openAIChatCompletionsLegacy: return "OpenAI Chat Completions (Legacy)"
        case .openRouterChatCompletions: return "OpenRouter Chat Completions"
        case .anthropicMessages: return "Anthropic Messages"
        case .foundationModels: return "Foundation Models"
        }
    }

    var isRemote: Bool {
        self != .foundationModels
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

extension LLMAuthKind {
    var requiresCredential: Bool {
        switch self {
        case .bearerToken, .xAPIKey, .codexChatGPTOAuth, .codexChatGPTDeviceCode:
            return true
        case .none, .customHeaders:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .bearerToken: return "Bearer Token"
        case .xAPIKey: return "x-api-key"
        case .customHeaders: return "Custom Headers"
        case .codexChatGPTOAuth: return "Codex OAuth"
        case .codexChatGPTDeviceCode: return "Codex Device Code"
        }
    }
}

/// One generation route exposed by a provider integration.
struct LLMProviderRouteProfile: Codable, Identifiable, Equatable {
    var id: LLMAdapterID { adapterID }
    var adapterID: LLMAdapterID
    var transportKind: LLMProviderTransportKind
    var defaultBaseURL: String
    var defaultAuthKind: LLMAuthKind
    var allowedAuthKinds: [LLMAuthKind]
    var isEnabled: Bool

    var requiresBaseURL: Bool {
        transportKind == .remoteHTTP
    }

    var requiresCredential: Bool {
        transportKind == .remoteHTTP && defaultAuthKind.requiresCredential
    }
}

/// Static provider metadata and its supported generation routes.
struct LLMProviderProfile: Codable, Identifiable, Equatable {
    var id: LLMProviderID
    var name: String
    var defaultAdapterID: LLMAdapterID
    var routes: [LLMProviderRouteProfile]
    var isEnabled: Bool

    var supportedAdapterIDs: [LLMAdapterID] {
        routes.filter(\.isEnabled).map(\.adapterID)
    }

    var defaultRoute: LLMProviderRouteProfile? {
        route(for: defaultAdapterID)
    }

    var transportKind: LLMProviderTransportKind {
        defaultRoute?.transportKind ?? .remoteHTTP
    }

    var defaultBaseURL: String {
        defaultRoute?.defaultBaseURL ?? ""
    }

    var authKind: LLMAuthKind {
        defaultRoute?.defaultAuthKind ?? .none
    }

    var requiresBaseURL: Bool {
        defaultRoute?.requiresBaseURL ?? false
    }

    var requiresCredential: Bool {
        defaultRoute?.requiresCredential ?? false
    }

    func route(for adapterID: LLMAdapterID) -> LLMProviderRouteProfile? {
        routes.first { $0.adapterID == adapterID && $0.isEnabled }
    }
}

/// Effective provider route passed into generation execution.
struct LLMResolvedProviderRoute: Equatable {
    var providerID: LLMProviderID
    var adapterID: LLMAdapterID
    var configuration: LLMProviderConfiguration
}
