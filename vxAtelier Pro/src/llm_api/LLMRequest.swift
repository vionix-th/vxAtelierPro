import Foundation

/// Fully resolved provider-neutral request ready for validation and adapter encoding.
struct LLMRequest: Codable, Equatable {
    var providerID: LLMProviderID
    var endpointFamily: LLMEndpointFamily
    var modelID: String
    var modelDescriptor: LLMModelDescriptor?
    var messages: [LLMMessage]
    var tools: [LLMToolDefinition]
    var options: LLMGenerationOptions

    init(
        providerID: LLMProviderID,
        endpointFamily: LLMEndpointFamily,
        modelID: String,
        modelDescriptor: LLMModelDescriptor? = nil,
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
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
