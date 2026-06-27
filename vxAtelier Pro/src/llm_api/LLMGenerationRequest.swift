import Foundation

/// Fully resolved provider-neutral request ready for validation and adapter encoding.
struct LLMGenerationRequest: Codable, Equatable {
    var providerID: LLMProviderID
    var adapterID: LLMAdapterID
    var modelID: String
    var modelCapabilities: [LLMModelCapability]
    var parameterMappings: [LLMParameterMapping]
    var parameterAvailability: [LLMParameterAvailability]
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var options: LLMGenerationOptions

    /// Creates a resolved request after runtime configuration has selected provider, adapter, and model.
    init(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String,
        modelCapabilities: [LLMModelCapability] = [],
        parameterMappings: [LLMParameterMapping] = [],
        parameterAvailability: [LLMParameterAvailability] = [],
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) {
        self.providerID = providerID
        self.adapterID = adapterID
        self.modelID = modelID
        self.modelCapabilities = modelCapabilities
        self.parameterMappings = parameterMappings
        self.parameterAvailability = parameterAvailability
        self.messages = messages
        self.tools = tools
        self.options = options
    }
}

/// Provider-neutral events emitted by adapters for streamed and complete responses.
enum LLMGenerationEvent: Equatable {
    case generationStarted(requestID: String?)
    case responseMetadata(LLMResponseMetadata)
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(LLMToolCall)
    case toolCallCompleted(LLMToolCall)
    case toolOutputCompleted(LLMToolOutput)
    case usage(LLMUsage)
    case generationCompleted(responseID: String?, modelID: String?)
}
