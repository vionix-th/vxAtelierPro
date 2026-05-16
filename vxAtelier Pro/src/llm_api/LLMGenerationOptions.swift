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
    }

    /// Retry behavior allowed before the run reaches tool execution.
    enum RetryPolicy: String, Codable, CaseIterable {
        case disabled
        case oneRetryBeforeTools
    }

    var systemPrompt: String
    var modelID: String?
    var temperature: Double?
    var topP: Double?
    var maxOutputTokens: Int?
    var topK: Int?
    var stop: [String]
    var responseFormat: ResponseFormat
    var reasoning: String?
    var reasoningSummary: String?
    var reasoningBudgetTokens: Int?
    var serviceTier: String?
    var textVerbosity: String?
    var streamMode: StreamMode
    var retryPolicy: RetryPolicy
    var providerExtras: [String: JSONValue]

    /// Creates provider-neutral generation options with conservative defaults.
    init(
        systemPrompt: String = "",
        modelID: String? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxOutputTokens: Int? = nil,
        topK: Int? = nil,
        stop: [String] = [],
        responseFormat: ResponseFormat = .text,
        reasoning: String? = nil,
        reasoningSummary: String? = nil,
        reasoningBudgetTokens: Int? = nil,
        serviceTier: String? = nil,
        textVerbosity: String? = nil,
        streamMode: StreamMode = .disabled,
        retryPolicy: RetryPolicy = .disabled,
        providerExtras: [String: JSONValue] = [:]
    ) {
        self.systemPrompt = systemPrompt
        self.modelID = modelID
        self.temperature = temperature
        self.topP = topP
        self.maxOutputTokens = maxOutputTokens
        self.topK = topK
        self.stop = stop
        self.responseFormat = responseFormat
        self.reasoning = reasoning
        self.reasoningSummary = reasoningSummary
        self.reasoningBudgetTokens = reasoningBudgetTokens
        self.serviceTier = serviceTier
        self.textVerbosity = textVerbosity
        self.streamMode = streamMode
        self.retryPolicy = retryPolicy
        self.providerExtras = providerExtras
    }
}
