import Foundation

enum LLMProviderID: String, Codable, CaseIterable, Identifiable {
    case openAIPlatform
    case openAICodexSubscription
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
        case .openAICodexSubscription: return "OpenAI Codex Subscription"
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
    case codexSubscription
}

enum LLMModality: String, Codable, CaseIterable {
    case text
    case image
    case audio
    case file
    case video
    case tool
    case reasoning
}

enum LLMSchemaFeature: String, Codable, CaseIterable {
    case tools
    case strictTools
    case jsonSchema
    case jsonObject
    case reasoning
    case usage
    case streaming
}

enum LLMRunStatus: String, Codable, CaseIterable {
    case pending
    case streaming
    case awaitingTools
    case completed
    case failed
    case cancelled
}

enum LLMToolCallStatus: String, Codable, CaseIterable {
    case readyToExecute
    case executing
    case completed
    case failed
    case cancelled
}

enum LLMProviderError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case invalidURL(String)
    case authUnavailable(String)
    case unsupportedCapability(String)
    case unsupportedParameter(String)
    case network(String)
    case provider(statusCode: Int, message: String, metadata: LLMResponseMetadata?)
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .invalidURL(let message): return message
        case .authUnavailable(let message): return message
        case .unsupportedCapability(let message): return message
        case .unsupportedParameter(let message): return message
        case .network(let message): return message
        case .provider(let statusCode, let message, _): return "Provider error \(statusCode): \(message)"
        case .decoding(let message): return message
        case .cancelled: return "Request cancelled."
        }
    }
}

struct LLMContentPart: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case text
        case image
        case audio
        case file
        case toolResult
        case reasoning
    }

    var id: UUID
    var kind: Kind
    var text: String?
    var mimeType: String?
    var dataBase64: String?
    var sourceURL: String?

    init(
        id: UUID = UUID(),
        kind: Kind = .text,
        text: String? = nil,
        mimeType: String? = nil,
        dataBase64: String? = nil,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.mimeType = mimeType
        self.dataBase64 = dataBase64
        self.sourceURL = sourceURL
    }
}

struct LLMMessage: Codable, Equatable, Identifiable {
    var id: UUID
    var role: String
    var content: [LLMContentPart]
    var toolCalls: [LLMToolCall]
    var toolCallID: String?

    init(
        id: UUID = UUID(),
        role: String,
        content: [LLMContentPart],
        toolCalls: [LLMToolCall] = [],
        toolCallID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    var displayText: String {
        content.compactMap(\.text).joined()
    }
}

struct LLMTool: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var description: String
    var parameters: JSONValue
}

struct LLMToolCall: Codable, Equatable, Identifiable {
    var id: String
    var callID: String?
    var index: Int
    var name: String
    var argumentsJSON: String

    init(id: String, callID: String? = nil, index: Int = 0, name: String, argumentsJSON: String) {
        self.id = id
        self.callID = callID
        self.index = index
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

struct LLMUsage: Codable, Equatable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?

    init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

struct LLMResponseMetadata: Codable, Equatable {
    var statusCode: Int?
    var requestID: String?
    var retryAfter: String?
    var rateLimitHeaders: [String: String]
    var headers: [String: String]

    init(
        statusCode: Int? = nil,
        requestID: String? = nil,
        retryAfter: String? = nil,
        rateLimitHeaders: [String: String] = [:],
        headers: [String: String] = [:]
    ) {
        self.statusCode = statusCode
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.rateLimitHeaders = rateLimitHeaders
        self.headers = headers
    }
}

struct LLMGenerationOptions: Codable, Equatable {
    enum ResponseFormat: String, Codable, CaseIterable {
        case text
        case jsonObject
        case jsonSchema
    }

    enum StreamMode: String, Codable, CaseIterable {
        case disabled
        case enabled
        case auto
    }

    enum RetryPolicy: String, Codable, CaseIterable {
        case disabled
        case oneRetryBeforeTools
    }

    var systemPrompt: String
    var modelID: String?
    var endpointFamily: LLMEndpointFamily?
    var temperature: Double?
    var topP: Double?
    var maxOutputTokens: Int?
    var stop: [String]
    var responseFormat: ResponseFormat
    var reasoning: String?
    var serviceTier: String?
    var streamMode: StreamMode
    var retryPolicy: RetryPolicy
    var providerExtras: [String: JSONValue]

    init(
        systemPrompt: String = "",
        modelID: String? = nil,
        endpointFamily: LLMEndpointFamily? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxOutputTokens: Int? = nil,
        stop: [String] = [],
        responseFormat: ResponseFormat = .text,
        reasoning: String? = nil,
        serviceTier: String? = nil,
        streamMode: StreamMode = .auto,
        retryPolicy: RetryPolicy = .disabled,
        providerExtras: [String: JSONValue] = [:]
    ) {
        self.systemPrompt = systemPrompt
        self.modelID = modelID
        self.endpointFamily = endpointFamily
        self.temperature = temperature
        self.topP = topP
        self.maxOutputTokens = maxOutputTokens
        self.stop = stop
        self.responseFormat = responseFormat
        self.reasoning = reasoning
        self.serviceTier = serviceTier
        self.streamMode = streamMode
        self.retryPolicy = retryPolicy
        self.providerExtras = providerExtras
    }
}

struct LLMModelDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var providerID: LLMProviderID
    var contextWindow: Int?
    var endpointFamilies: [LLMEndpointFamily]
    var modalities: [LLMModality]
    var supportedParameters: [String]
    var schemaFeatures: [LLMSchemaFeature]
    var rawMetadataJSON: String?

    init(
        id: String,
        displayName: String? = nil,
        providerID: LLMProviderID,
        contextWindow: Int? = nil,
        endpointFamilies: [LLMEndpointFamily],
        modalities: [LLMModality] = [.text],
        supportedParameters: [String] = [],
        schemaFeatures: [LLMSchemaFeature] = [],
        rawMetadataJSON: String? = nil
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.providerID = providerID
        self.contextWindow = contextWindow
        self.endpointFamilies = endpointFamilies
        self.modalities = modalities
        self.supportedParameters = supportedParameters
        self.schemaFeatures = schemaFeatures
        self.rawMetadataJSON = rawMetadataJSON
    }
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

struct LLMRequest: Codable, Equatable {
    var providerID: LLMProviderID
    var endpointFamily: LLMEndpointFamily
    var modelID: String
    var modelDescriptor: LLMModelDescriptor?
    var messages: [LLMMessage]
    var tools: [LLMTool]
    var options: LLMGenerationOptions

    init(
        providerID: LLMProviderID,
        endpointFamily: LLMEndpointFamily,
        modelID: String,
        modelDescriptor: LLMModelDescriptor? = nil,
        messages: [LLMMessage],
        tools: [LLMTool] = [],
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) {
        self.providerID = providerID
        self.endpointFamily = endpointFamily
        self.modelID = modelID
        self.modelDescriptor = modelDescriptor
        self.messages = messages
        self.tools = tools
        self.options = options
    }
}

enum LLMStreamEvent: Equatable {
    case runStarted(requestID: String?)
    case responseMetadata(LLMResponseMetadata)
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(LLMToolCall)
    case toolCallCompleted(LLMToolCall)
    case usage(LLMUsage)
    case runCompleted(responseID: String?, modelID: String?)
}
