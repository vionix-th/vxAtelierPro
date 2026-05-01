import Foundation

struct LLMCapabilityValidator {
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
        if options.temperature != nil { try requireParameter("temperature", request: request, profile: profile) }
        if options.topP != nil { try requireParameter("top_p", request: request, profile: profile) }
        if options.maxOutputTokens != nil {
            guard supportsParameter("max_output_tokens", request: request, profile: profile)
                    || supportsParameter("max_tokens", request: request, profile: profile) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support max output tokens for \(request.modelID).")
            }
        }
        if !options.stop.isEmpty { try requireParameter("stop", request: request, profile: profile) }
        if options.reasoning != nil {
            guard hasSchemaFeature(.reasoning, request: request, profile: profile) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support reasoning for \(request.modelID).")
            }
        }
        if options.serviceTier != nil { try requireParameter("service_tier", request: request, profile: profile) }
        switch options.responseFormat {
        case .text:
            break
        case .jsonObject:
            try requireParameter("response_format", request: request, profile: profile)
            guard hasSchemaFeature(.jsonObject, request: request, profile: profile) else {
                throw LLMProviderError.unsupportedParameter("\(profile.name) does not support JSON object response format for \(request.modelID).")
            }
        case .jsonSchema:
            try requireParameter("response_format", request: request, profile: profile)
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

    private static func requireParameter(_ parameter: String, request: LLMRequest, profile: LLMProviderProfile) throws {
        guard supportsParameter(parameter, request: request, profile: profile) else {
            throw LLMProviderError.unsupportedParameter("\(profile.name) does not support \(parameter) for \(request.modelID).")
        }
    }

    private static func supportsParameter(_ parameter: String, request: LLMRequest, profile: LLMProviderProfile) -> Bool {
        if let supported = request.modelDescriptor?.supportedParameters, !supported.isEmpty {
            return supported.contains(parameter) && profile.supportedParameters.contains(parameter)
        }
        return profile.supportedParameters.contains(parameter)
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
