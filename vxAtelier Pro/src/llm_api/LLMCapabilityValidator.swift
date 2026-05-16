import Foundation

/// Validates a resolved LLM request against provider and model capabilities.
struct LLMCapabilityValidator {
    /// Performs preflight checks before a run is persisted or sent to a provider.
    static func validate(_ request: LLMRequest, profile: LLMProviderProfile) throws {
        guard profile.isEnabled else {
            throw LLMProviderError.authUnavailable("\(profile.name) is disabled.")
        }
        try validateEndpoint(request, profile: profile)
        try validateStreaming(for: request, profile: profile)
        try validateParameters(request, profile: profile)
        try validateContent(request, profile: profile)
        try validateToolReplay(request)
    }

    /// Rejects unsupported forced streaming.
    static func validateStreaming(for request: LLMRequest, profile: LLMProviderProfile) throws {
        guard request.options.streamMode == .enabled else { return }
        guard supportsCapability(.streaming, request: request) else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support streaming for \(request.modelID).")
        }
    }

    /// Returns the explicit stream flag selected by conversation parameters.
    static func streamEnabled(for request: LLMRequest) -> Bool {
        switch request.options.streamMode {
        case .disabled:
            return false
        case .enabled:
            return true
        }
    }

    /// Confirms that both provider profile and model metadata allow the selected adapter.
    private static func validateEndpoint(_ request: LLMRequest, profile: LLMProviderProfile) throws {
        guard profile.supportedAdapterIDs.contains(request.adapterID) else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support \(request.adapterID.rawValue).")
        }
    }

    /// Confirms requested generation options are mapped and supported by the provider/model pair.
    private static func validateParameters(_ request: LLMRequest, profile: LLMProviderProfile) throws {
        let options = request.options
        let mappings = LLMParameterMappingResolver.resolve(
            adapterID: request.adapterID,
            mappings: request.parameterMappings
        )
        if options.temperature != nil { try requireMapping(.temperature, mappings: mappings, request: request, profile: profile) }
        if options.topP != nil { try requireMapping(.topP, mappings: mappings, request: request, profile: profile) }
        if options.maxOutputTokens != nil { try requireMapping(.maxOutputTokens, mappings: mappings, request: request, profile: profile) }
        if !options.stop.isEmpty { try requireMapping(.stopSequences, mappings: mappings, request: request, profile: profile) }
        if options.reasoning != nil {
            try requireMapping(.reasoningEffort, mappings: mappings, request: request, profile: profile)
            guard supportsCapability(.reasoning, request: request) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support reasoning for \(request.modelID).")
            }
        }
        if options.serviceTier != nil { try requireMapping(.serviceTier, mappings: mappings, request: request, profile: profile) }
        switch options.responseFormat {
        case .text:
            break
        case .jsonObject:
            try requireMapping(.responseFormat, mappings: mappings, request: request, profile: profile)
            guard supportsCapability(.jsonObject, request: request) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support JSON object response format for \(request.modelID).")
            }
        case .jsonSchema:
            try requireMapping(.responseFormat, mappings: mappings, request: request, profile: profile)
            guard supportsCapability(.jsonSchema, request: request) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support JSON schema response format for \(request.modelID).")
            }
            guard request.options.providerExtras["json_schema"]?.objectValue != nil else {
                throw LLMProviderError.unsupportedParameter("response_format json_schema requires providerExtras.json_schema object.")
            }
        }
        if !request.tools.isEmpty {
            guard supportsCapability(.tools, request: request) else {
                throw LLMProviderError.unsupportedCapability("\(profile.name) does not support tools for \(request.modelID).")
            }
        }
        let availability = LLMParameterAvailabilityMappingResolver.resolve(
            adapterID: request.adapterID,
            availability: request.parameterAvailability
        )
        for descriptor in availability.values where descriptor.isAvailable && descriptor.semanticParameterID.isProviderMappable {
            let value = request.options.jsonValue(for: descriptor.semanticParameterID)
            if descriptor.isRequired && value == nil && descriptor.defaultValue == nil {
                throw LLMProviderError.unsupportedParameter("\(descriptor.semanticParameterID.rawValue) is required for \(request.modelID).")
            }
            if value != nil || descriptor.defaultValue != nil || descriptor.isRequired {
                try requireMapping(descriptor.semanticParameterID, mappings: mappings, request: request, profile: profile)
            }
        }
    }

    /// Confirms message content modalities are supported by the provider/model pair.
    private static func validateContent(_ request: LLMRequest, profile: LLMProviderProfile) throws {
        for message in request.messages {
            for part in message.content {
                switch part.kind {
                case .text, .toolResult, .reasoning:
                    continue
                case .image:
                    guard supportsCapability(.image, request: request) else {
                        throw LLMProviderError.unsupportedCapability("\(profile.name) does not support image content for \(request.modelID).")
                    }
                case .file:
                    guard request.adapterID == .openAIResponses,
                          supportsCapability(.file, request: request) else {
                        throw LLMProviderError.unsupportedCapability("\(profile.name) does not support file content for \(request.adapterID.rawValue).")
                    }
                case .audio:
                    guard supportsCapability(.audio, request: request) else {
                        throw LLMProviderError.unsupportedCapability("\(profile.name) does not support audio content.")
                    }
                }
            }
        }
    }

    /// Confirms assistant tool calls and tool results form a valid provider replay sequence.
    private static func validateToolReplay(_ request: LLMRequest) throws {
        var knownToolIDs = Set<String>()
        var answeredToolIDs = Set<String>()
        var pendingToolIDs: [String] = []

        for message in request.messages {
            if message.role != "tool", !pendingToolIDs.isEmpty {
                throw pendingToolResultError(for: request)
            }

            if message.role == "assistant" {
                let ids = message.toolCalls.sorted { $0.index < $1.index }.map { $0.callID ?? $0.id }
                let uniqueIDs = Set(ids)
                guard uniqueIDs.count == ids.count else {
                    throw LLMProviderError.unsupportedParameter("Assistant tool calls must have unique ids.")
                }
                guard knownToolIDs.isDisjoint(with: uniqueIDs) else {
                    throw LLMProviderError.unsupportedParameter("Assistant tool calls must have unique ids.")
                }
                knownToolIDs.formUnion(ids)
                pendingToolIDs = ids
                continue
            }

            if message.role == "tool" {
                guard let toolCallID = message.toolCallID, !toolCallID.isEmpty else {
                    throw LLMProviderError.unsupportedParameter("Tool result message requires toolCallID.")
                }
                guard knownToolIDs.contains(toolCallID) else {
                    throw LLMProviderError.unsupportedParameter("Tool result \(toolCallID) has no prior assistant tool call.")
                }
                guard !answeredToolIDs.contains(toolCallID) else {
                    throw LLMProviderError.unsupportedParameter("Tool result \(toolCallID) is duplicated.")
                }
                guard let index = pendingToolIDs.firstIndex(of: toolCallID) else {
                    throw pendingToolResultError(for: request)
                }
                pendingToolIDs.remove(at: index)
                answeredToolIDs.insert(toolCallID)
                continue
            }
        }

        if !pendingToolIDs.isEmpty {
            throw LLMProviderError.unsupportedParameter("Assistant tool calls must be followed by tool results.")
        }
    }

    /// Returns the provider-specific error for an interrupted tool-result sequence.
    private static func pendingToolResultError(for request: LLMRequest) -> LLMProviderError {
        if request.adapterID == .anthropicMessages {
            return .unsupportedParameter("Anthropic tool_result must immediately follow its assistant tool_use.")
        }
        return .unsupportedParameter("Tool result must immediately follow assistant tool call.")
    }

    /// Requires an active provider mapping before a semantic option is encoded.
    private static func requireMapping(
        _ parameterID: LLMParameterID,
        mappings: [LLMParameterID: LLMParameterMappingDescriptor],
        request: LLMRequest,
        profile: LLMProviderProfile
    ) throws {
        guard let mapping = mappings[parameterID], mapping.encodingKind != .disabled else {
            throw LLMProviderError.unsupportedParameter("\(profile.name) does not support \(parameterID.rawValue) for \(request.modelID).")
        }
    }

    /// Resolves a capability against persisted model metadata.
    private static func supportsCapability(_ capability: LLMModelCapability, request: LLMRequest) -> Bool {
        request.modelCapabilities.contains(capability)
    }
}
