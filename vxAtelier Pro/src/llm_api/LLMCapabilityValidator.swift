import Foundation

/// Validates a resolved LLM request against provider and model capabilities.
struct LLMCapabilityValidator {
    /// Performs preflight checks before a run is persisted or sent to a provider.
    static func validate(_ request: LLMRequest, profile: LLMProviderProfile) throws {
        guard profile.isEnabled else {
            throw LLMProviderError.authUnavailable("\(profile.name) is disabled.")
        }
        try validateEndpoint(request, profile: profile)
        _ = try resolveStreamEnabled(for: request, profile: profile)
        try validateParameters(request, profile: profile)
        try validateContent(request, profile: profile)
        try validateToolReplay(request)
    }

    /// Resolves `.auto` streaming behavior and rejects unsupported forced streaming.
    static func resolveStreamEnabled(for request: LLMRequest, profile: LLMProviderProfile) throws -> Bool {
        let supportsStreaming = hasSchemaFeature(.streaming, request: request, profile: profile)
        switch request.options.streamMode {
        case .disabled:
            return false
        case .enabled:
            guard supportsStreaming else {
                throw LLMProviderError.unsupportedCapability("\(profile.name) does not support streaming for \(request.modelID).")
            }
            return true
        case .auto:
            return supportsStreaming
        }
    }

    private static func validateEndpoint(_ request: LLMRequest, profile: LLMProviderProfile) throws {
        guard profile.supportedEndpointFamilies.contains(request.endpointFamily) else {
            throw LLMProviderError.unsupportedCapability("\(profile.name) does not support \(request.endpointFamily.rawValue).")
        }
        guard let model = request.modelDescriptor, !model.endpointFamilies.isEmpty else { return }
        guard model.endpointFamilies.contains(request.endpointFamily) else {
            throw LLMProviderError.unsupportedCapability("\(request.modelID) does not support \(request.endpointFamily.rawValue).")
        }
    }

    private static func validateParameters(_ request: LLMRequest, profile: LLMProviderProfile) throws {
        let options = request.options
        let mappings = LLMParameterMappingResolver.resolve(
            providerID: request.providerID,
            endpointFamily: request.endpointFamily,
            modelID: request.modelID,
            modelDescriptor: request.modelDescriptor
        )
        if options.temperature != nil { try requireMapping(.temperature, mappings: mappings, request: request, profile: profile) }
        if options.topP != nil { try requireMapping(.topP, mappings: mappings, request: request, profile: profile) }
        if options.maxOutputTokens != nil { try requireMapping(.maxOutputTokens, mappings: mappings, request: request, profile: profile) }
        if !options.stop.isEmpty { try requireMapping(.stopSequences, mappings: mappings, request: request, profile: profile) }
        if options.reasoning != nil {
            try requireMapping(.reasoningEffort, mappings: mappings, request: request, profile: profile)
            guard hasSchemaFeature(.reasoning, request: request, profile: profile) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support reasoning for \(request.modelID).")
            }
        }
        if options.serviceTier != nil { try requireMapping(.serviceTier, mappings: mappings, request: request, profile: profile) }
        switch options.responseFormat {
        case .text:
            break
        case .jsonObject:
            try requireMapping(.responseFormat, mappings: mappings, request: request, profile: profile)
            guard hasSchemaFeature(.jsonObject, request: request, profile: profile) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support JSON object response format for \(request.modelID).")
            }
        case .jsonSchema:
            try requireMapping(.responseFormat, mappings: mappings, request: request, profile: profile)
            guard hasSchemaFeature(.jsonSchema, request: request, profile: profile) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support JSON schema response format for \(request.modelID).")
            }
            guard request.options.providerExtras["json_schema"]?.objectValue != nil else {
                throw LLMProviderError.unsupportedParameter("response_format json_schema requires providerExtras.json_schema object.")
            }
        }
        if !request.tools.isEmpty {
            guard hasSchemaFeature(.tools, request: request, profile: profile) else {
                throw LLMProviderError.unsupportedCapability("\(profile.name) does not support tools for \(request.modelID).")
            }
        }
        for mapping in mappings.values where mapping.isEnabled && mapping.isRequired {
            if request.options.jsonValue(for: mapping.semanticParameterID) == nil && mapping.defaultValue == nil {
                throw LLMProviderError.unsupportedParameter("\(mapping.semanticParameterID.rawValue) is required for \(request.modelID).")
            }
        }
    }

    private static func validateContent(_ request: LLMRequest, profile: LLMProviderProfile) throws {
        for message in request.messages {
            for part in message.content {
                switch part.kind {
                case .text, .toolResult, .reasoning:
                    continue
                case .image:
                    guard supportsModality(.image, request: request, profile: profile) else {
                        throw LLMProviderError.unsupportedCapability("\(profile.name) does not support image content for \(request.modelID).")
                    }
                case .file:
                    guard request.endpointFamily == .responses,
                          supportsModality(.file, request: request, profile: profile) else {
                        throw LLMProviderError.unsupportedCapability("\(profile.name) does not support file content for \(request.endpointFamily.rawValue).")
                    }
                case .audio:
                    throw LLMProviderError.unsupportedCapability("\(profile.name) does not support audio content.")
                }
            }
        }
    }

    private static func validateToolReplay(_ request: LLMRequest) throws {
        var knownToolIDs = Set<String>()
        var answeredToolIDs = Set<String>()
        var immediateAnthropicToolIDs: [String] = []

        for message in request.messages {
            if message.role == "assistant" {
                let ids = message.toolCalls.sorted { $0.index < $1.index }.map { $0.callID ?? $0.id }
                let uniqueIDs = Set(ids)
                guard uniqueIDs.count == ids.count else {
                    throw LLMProviderError.unsupportedParameter("Assistant tool calls must have unique ids.")
                }
                knownToolIDs.formUnion(ids)
                if request.endpointFamily == .anthropicMessages {
                    immediateAnthropicToolIDs = ids
                }
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
                if request.endpointFamily == .anthropicMessages {
                    guard let index = immediateAnthropicToolIDs.firstIndex(of: toolCallID) else {
                        throw LLMProviderError.unsupportedParameter("Anthropic tool_result must immediately follow its assistant tool_use.")
                    }
                    immediateAnthropicToolIDs.remove(at: index)
                }
                answeredToolIDs.insert(toolCallID)
                continue
            }

            if request.endpointFamily == .anthropicMessages, !immediateAnthropicToolIDs.isEmpty {
                throw LLMProviderError.unsupportedParameter("Anthropic tool_result must immediately follow its assistant tool_use.")
            }
        }
    }

    private static func requireMapping(
        _ parameterID: LLMParameterID,
        mappings: [LLMParameterID: LLMParameterMappingDescriptor],
        request: LLMRequest,
        profile: LLMProviderProfile
    ) throws {
        guard let mapping = mappings[parameterID], mapping.isEnabled, mapping.encodingKind != .disabled else {
            throw LLMProviderError.unsupportedParameter("\(profile.name) does not support \(parameterID.rawValue) for \(request.modelID).")
        }
    }

    private static func hasSchemaFeature(_ feature: LLMSchemaFeature, request: LLMRequest, profile: LLMProviderProfile) -> Bool {
        if let features = request.modelDescriptor?.schemaFeatures, !features.isEmpty {
            return features.contains(feature) && profile.schemaFeatures.contains(feature)
        }
        return profile.schemaFeatures.contains(feature)
    }

    private static func supportsModality(_ modality: LLMModality, request: LLMRequest, profile: LLMProviderProfile) -> Bool {
        if let modalities = request.modelDescriptor?.modalities, !modalities.isEmpty {
            return modalities.contains(modality) && profile.modalities.contains(modality)
        }
        return profile.modalities.contains(modality)
    }
}
