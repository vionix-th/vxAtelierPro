import Foundation

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

    var id: String { rawValue }

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

enum LLMEndpointFamily: String, Codable, CaseIterable, Identifiable {
    case chatCompletions
    case responses
    case anthropicMessages
    case models

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatCompletions: return "Chat Completions"
        case .responses: return "Responses"
        case .anthropicMessages: return "Anthropic Messages"
        case .models: return "Models"
        }
    }
}

enum LLMAuthKind: String, Codable, CaseIterable {
    case none
    case bearerToken
    case xAPIKey
    case customHeaders
    case chatGPTOAuth
    case chatGPTDeviceCode
    case chatGPTCodexToken
}

struct LLMProviderProfile: Codable, Identifiable, Equatable {
    var id: LLMProviderID
    var name: String
    var defaultBaseURL: String
    var authKind: LLMAuthKind
    var defaultEndpointFamily: LLMEndpointFamily
    var supportedEndpointFamilies: [LLMEndpointFamily]
    var defaultModelID: String?
    var endpointPaths: [LLMEndpointFamily: String]
    var supportedParameters: [String]
    var schemaFeatures: [LLMSchemaFeature]
    var modalities: [LLMModality]
    var isEnabled: Bool
}
