import Foundation

/// Encoding strategy for a semantic parameter in a provider request body.
enum LLMParameterEncodingKind: String, Codable, CaseIterable, Identifiable {
    case scalarKey
    case structuredPreset
    case disabled

    /// Exposes the raw encoding key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing encoding name for model mapping controls.
    var displayName: String {
        switch self {
        case .scalarKey: return "Scalar Key"
        case .structuredPreset: return "Structured Preset"
        case .disabled: return "Disabled"
        }
    }
}

/// Known structured encodings that cannot be represented by a scalar wire key.
enum LLMParameterStructuredPreset: String, Codable, CaseIterable, Identifiable {
    case openAIChatResponseFormat
    case openAIResponsesTextFormat
    case openAIResponsesReasoning

    /// Exposes the raw preset key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing preset name for model mapping controls.
    var displayName: String {
        switch self {
        case .openAIChatResponseFormat: return "OpenAI Chat Response Format"
        case .openAIResponsesTextFormat: return "OpenAI Responses Text Format"
        case .openAIResponsesReasoning: return "OpenAI Responses Reasoning"
        }
    }
}

/// Mapping from one semantic parameter to one provider endpoint encoding.
struct LLMParameterMappingDescriptor: Codable, Equatable, Identifiable {
    /// Combines endpoint and semantic parameter so one model can store per-endpoint mappings.
    var id: String { "\(endpointFamily.rawValue):\(semanticParameterID.rawValue)" }
    var endpointFamily: LLMEndpointFamily
    var semanticParameterID: LLMParameterID
    var isEnabled: Bool
    var isRequired: Bool
    var encodingKind: LLMParameterEncodingKind
    var wireKey: String
    var structuredPreset: LLMParameterStructuredPreset?
    var defaultValue: JSONValue?

    /// Creates a provider mapping for a semantic parameter at one endpoint.
    init(
        endpointFamily: LLMEndpointFamily,
        semanticParameterID: LLMParameterID,
        isEnabled: Bool = true,
        isRequired: Bool = false,
        encodingKind: LLMParameterEncodingKind = .scalarKey,
        wireKey: String = "",
        structuredPreset: LLMParameterStructuredPreset? = nil,
        defaultValue: JSONValue? = nil
    ) {
        self.endpointFamily = endpointFamily
        self.semanticParameterID = semanticParameterID
        self.isEnabled = isEnabled
        self.isRequired = isRequired
        self.encodingKind = encodingKind
        self.wireKey = wireKey
        self.structuredPreset = structuredPreset
        self.defaultValue = defaultValue
    }
}

/// Built-in parameter mappings for supported provider endpoint families.
enum LLMParameterMappingCatalog {
    /// Returns default mappings for a provider, endpoint family, and model.
    static func defaults(
        providerID: LLMProviderID,
        endpointFamily: LLMEndpointFamily,
        modelID: String
    ) -> [LLMParameterMappingDescriptor] {
        switch endpointFamily {
        case .responses:
            guard providerID == .openAIPlatform else { return [] }
            return openAIResponsesDefaults()
        case .chatCompletions:
            if providerID == .openAIPlatform {
                return openAIChatDefaults(modelID: modelID)
            }
            if [.openRouter, .lmStudio, .ollama, .xAI, .deepSeek, .customOpenAICompatible].contains(providerID) {
                return openAICompatibleChatDefaults()
            }
            return []
        case .anthropicMessages:
            guard providerID == .anthropic else { return [] }
            return anthropicMessagesDefaults()
        case .models:
            return []
        }
    }

    /// Selects the OpenAI chat token-limit key for the requested model generation.
    private static func openAIChatDefaults(modelID: String) -> [LLMParameterMappingDescriptor] {
        let maxTokenWireKey = modelID.lowercased().hasPrefix("gpt-5")
            ? "max_completion_tokens"
            : "max_tokens"
        return commonChatDefaults(endpointFamily: .chatCompletions, maxTokenWireKey: maxTokenWireKey)
    }

    /// Defaults for OpenAI-compatible chat APIs that follow the legacy token-limit key.
    private static func openAICompatibleChatDefaults() -> [LLMParameterMappingDescriptor] {
        commonChatDefaults(endpointFamily: .chatCompletions, maxTokenWireKey: "max_tokens")
    }

    /// Builds mappings shared by OpenAI-compatible chat endpoints.
    private static func commonChatDefaults(
        endpointFamily: LLMEndpointFamily,
        maxTokenWireKey: String
    ) -> [LLMParameterMappingDescriptor] {
        [
            .init(endpointFamily: endpointFamily, semanticParameterID: .maxOutputTokens, wireKey: maxTokenWireKey),
            .init(endpointFamily: endpointFamily, semanticParameterID: .temperature, wireKey: "temperature"),
            .init(endpointFamily: endpointFamily, semanticParameterID: .topP, wireKey: "top_p"),
            .init(endpointFamily: endpointFamily, semanticParameterID: .stopSequences, wireKey: "stop"),
            .init(
                endpointFamily: endpointFamily,
                semanticParameterID: .responseFormat,
                encodingKind: .structuredPreset,
                structuredPreset: .openAIChatResponseFormat
            )
        ]
    }

    /// Defaults for OpenAI Responses endpoint structured and scalar parameters.
    private static func openAIResponsesDefaults() -> [LLMParameterMappingDescriptor] {
        [
            .init(endpointFamily: .responses, semanticParameterID: .maxOutputTokens, wireKey: "max_output_tokens"),
            .init(endpointFamily: .responses, semanticParameterID: .temperature, wireKey: "temperature"),
            .init(endpointFamily: .responses, semanticParameterID: .topP, wireKey: "top_p"),
            .init(
                endpointFamily: .responses,
                semanticParameterID: .responseFormat,
                encodingKind: .structuredPreset,
                structuredPreset: .openAIResponsesTextFormat
            ),
            .init(
                endpointFamily: .responses,
                semanticParameterID: .reasoningEffort,
                encodingKind: .structuredPreset,
                structuredPreset: .openAIResponsesReasoning
            ),
            .init(endpointFamily: .responses, semanticParameterID: .serviceTier, wireKey: "service_tier")
        ]
    }

    /// Defaults required by Anthropic Messages, including the fallback max-token value.
    private static func anthropicMessagesDefaults() -> [LLMParameterMappingDescriptor] {
        [
            .init(
                endpointFamily: .anthropicMessages,
                semanticParameterID: .maxOutputTokens,
                isRequired: true,
                wireKey: "max_tokens",
                defaultValue: .integer(AppDefaults.Anthropic.max_tokens)
            ),
            .init(endpointFamily: .anthropicMessages, semanticParameterID: .temperature, wireKey: "temperature"),
            .init(endpointFamily: .anthropicMessages, semanticParameterID: .topP, wireKey: "top_p"),
            .init(endpointFamily: .anthropicMessages, semanticParameterID: .stopSequences, wireKey: "stop_sequences")
        ]
    }
}

/// Resolves model-specific mappings with built-in defaults as the fallback.
struct LLMParameterMappingResolver {
    /// Returns active mappings keyed by semantic parameter.
    static func resolve(
        providerID: LLMProviderID,
        endpointFamily: LLMEndpointFamily,
        modelID: String,
        modelDescriptor: LLMModelDescriptor?
    ) -> [LLMParameterID: LLMParameterMappingDescriptor] {
        let persisted = modelDescriptor?.parameterMappings.filter { $0.endpointFamily == endpointFamily } ?? []
        let source = persisted.isEmpty
            ? LLMParameterMappingCatalog.defaults(providerID: providerID, endpointFamily: endpointFamily, modelID: modelID)
            : persisted
        return Dictionary(uniqueKeysWithValues: source.map { ($0.semanticParameterID, $0) })
    }
}

/// Encodes scalar semantic parameters into a provider request body.
enum LLMParameterRequestEncoder {
    /// Applies only scalar-key mappings; structured presets are adapter-specific.
    static func applyScalarOptions(
        _ options: LLMGenerationOptions,
        to body: inout [String: JSONValue],
        mappings: [LLMParameterID: LLMParameterMappingDescriptor]
    ) throws {
        for mapping in mappings.values where mapping.isEnabled {
            guard mapping.encodingKind == .scalarKey else { continue }
            guard let value = options.jsonValue(for: mapping.semanticParameterID) ?? mapping.defaultValue else {
                if mapping.isRequired {
                    throw LLMProviderError.unsupportedParameter("\(mapping.semanticParameterID.rawValue) is required.")
                }
                continue
            }
            guard !mapping.wireKey.isEmpty else {
                throw LLMProviderError.unsupportedParameter("\(mapping.semanticParameterID.rawValue) has no wire key.")
            }
            body[mapping.wireKey] = value
        }
    }
}

/// Semantic parameter extraction for provider request encoding.
extension LLMGenerationOptions {
    /// Returns the JSON value for a semantic parameter when the option is set.
    func jsonValue(for parameterID: LLMParameterID) -> JSONValue? {
        switch parameterID {
        case .model:
            return modelID.map { .string($0) }
        case .systemPrompt:
            return systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .string(systemPrompt)
        case .maxOutputTokens:
            return maxOutputTokens.map { .integer($0) }
        case .temperature:
            return temperature.map { .number($0) }
        case .topP:
            return topP.map { .number($0) }
        case .stopSequences:
            return stop.isEmpty ? nil : .array(stop.map { .string($0) })
        case .responseFormat:
            return .string(responseFormat.semanticRawValue)
        case .reasoningEffort:
            return reasoning.flatMap { $0.isEmpty ? nil : .string($0) }
        case .serviceTier:
            return serviceTier.flatMap { $0.isEmpty ? nil : .string($0) }
        }
    }
}

/// Response-format normalization for persisted and provider-neutral values.
extension LLMGenerationOptions.ResponseFormat {
    /// Normalized value used by semantic parameter mappings.
    var semanticRawValue: String {
        switch self {
        case .text: return "text"
        case .jsonObject: return "json_object"
        case .jsonSchema: return "json_schema"
        }
    }

    /// Parses persisted legacy and semantic response-format values.
    static func fromSemanticRawValue(_ value: String) -> Self {
        switch value {
        case "json_object", "jsonObject":
            return .jsonObject
        case "json_schema", "jsonSchema":
            return .jsonSchema
        default:
            return .text
        }
    }
}
