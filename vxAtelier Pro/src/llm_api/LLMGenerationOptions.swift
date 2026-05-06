import Foundation

/// Provider-neutral generation controls resolved from conversation and model settings.
struct LLMGenerationOptions: Codable, Equatable {
    /// Requested structure for assistant text output.
    enum ResponseFormat: String, Codable, CaseIterable {
        case text
        case jsonObject
        case jsonSchema
    }

    /// Caller preference for streamed versus complete responses.
    enum StreamMode: String, Codable, CaseIterable {
        case disabled
        case enabled
        case auto
    }

    /// Retry behavior allowed before the run reaches tool execution.
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
