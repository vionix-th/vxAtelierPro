import Foundation

enum ModelParameterEncodingKind: String, Codable, CaseIterable, Identifiable {
    case scalarKey
    case structuredPreset
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scalarKey: return "Scalar Key"
        case .structuredPreset: return "Structured Preset"
        case .disabled: return "Disabled"
        }
    }
}

enum ModelParameterStructuredPreset: String, Codable, CaseIterable, Identifiable {
    case openAIChatResponseFormat
    case openAIResponsesTextFormat
    case openAIResponsesReasoning

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAIChatResponseFormat: return "OpenAI Chat Response Format"
        case .openAIResponsesTextFormat: return "OpenAI Responses Text Format"
        case .openAIResponsesReasoning: return "OpenAI Responses Reasoning"
        }
    }
}

struct LLMParameterMappingDescriptor: Codable, Equatable, Identifiable {
    var id: String { "\(endpointFamily.rawValue):\(semanticParameterID.rawValue)" }
    var endpointFamily: LLMEndpointFamily
    var semanticParameterID: LLMParameterID
    var isEnabled: Bool
    var isRequired: Bool
    var encodingKind: ModelParameterEncodingKind
    var wireKey: String
    var structuredPreset: ModelParameterStructuredPreset?
    var defaultValue: JSONValue?

    init(
        endpointFamily: LLMEndpointFamily,
        semanticParameterID: LLMParameterID,
        isEnabled: Bool = true,
        isRequired: Bool = false,
        encodingKind: ModelParameterEncodingKind = .scalarKey,
        wireKey: String = "",
        structuredPreset: ModelParameterStructuredPreset? = nil,
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

enum LLMParameterMappingCatalog {
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

    private static func openAIChatDefaults(modelID: String) -> [LLMParameterMappingDescriptor] {
        let maxTokenWireKey = modelID.lowercased().hasPrefix("gpt-5")
            ? "max_completion_tokens"
            : "max_tokens"
        return commonChatDefaults(endpointFamily: .chatCompletions, maxTokenWireKey: maxTokenWireKey)
    }

    private static func openAICompatibleChatDefaults() -> [LLMParameterMappingDescriptor] {
        commonChatDefaults(endpointFamily: .chatCompletions, maxTokenWireKey: "max_tokens")
    }

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

struct LLMParameterMappingResolver {
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

enum LLMParameterRequestEncoder {
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

extension LLMGenerationOptions {
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

extension LLMGenerationOptions.ResponseFormat {
    var semanticRawValue: String {
        switch self {
        case .text: return "text"
        case .jsonObject: return "json_object"
        case .jsonSchema: return "json_schema"
        }
    }

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
