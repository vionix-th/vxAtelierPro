import Foundation

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
