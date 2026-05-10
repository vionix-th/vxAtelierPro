import Foundation

/// Fully resolved provider-neutral request ready for validation and adapter encoding.
struct LLMRequest: Codable, Equatable {
    var providerID: LLMProviderID
    var adapterID: LLMAdapterID
    var modelID: String
    var modelCapabilities: [LLMModelCapability]
    var parameterMappings: [LLMParameterMappingDescriptor]
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var options: LLMGenerationOptions

    /// Creates a resolved request after runtime configuration has selected provider, adapter, and model.
    init(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String,
        modelCapabilities: [LLMModelCapability] = [],
        parameterMappings: [LLMParameterMappingDescriptor] = [],
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) {
        self.providerID = providerID
        self.adapterID = adapterID
        self.modelID = modelID
        self.modelCapabilities = modelCapabilities
        self.parameterMappings = parameterMappings
        self.messages = messages
        self.tools = tools
        self.options = options
    }
}

/// Provider-neutral events emitted by adapters for streamed and complete responses.
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
