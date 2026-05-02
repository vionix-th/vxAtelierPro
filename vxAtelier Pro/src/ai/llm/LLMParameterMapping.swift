import Foundation

enum LLMApplicationParameterID: String, Codable, CaseIterable, Identifiable {
    case model
    case systemPrompt = "system_prompt"
    case maxOutputTokens = "max_output_tokens"
    case temperature
    case topP = "top_p"
    case stopSequences = "stop_sequences"
    case responseFormat = "response_format"
    case reasoningEffort = "reasoning_effort"
    case serviceTier = "service_tier"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .model: return "Model"
        case .systemPrompt: return "System Prompt"
        case .maxOutputTokens: return "Max Output Tokens"
        case .temperature: return "Temperature"
        case .topP: return "Top P"
        case .stopSequences: return "Stop Sequences"
        case .responseFormat: return "Response Format"
        case .reasoningEffort: return "Reasoning Effort"
        case .serviceTier: return "Service Tier"
        }
    }

    var parameterDescription: String {
        switch self {
        case .model: return "Model identifier used for this conversation"
        case .systemPrompt: return "Instructions for the assistant"
        case .maxOutputTokens: return "Maximum number of generated tokens"
        case .temperature: return "Sampling temperature"
        case .topP: return "Nucleus sampling probability"
        case .stopSequences: return "Stop sequences, one per line"
        case .responseFormat: return "Generated response format"
        case .reasoningEffort: return "Reasoning effort control"
        case .serviceTier: return "Provider service tier"
        }
    }

    var valueType: AiArgumentValueType {
        switch self {
        case .maxOutputTokens:
            return .integer
        case .temperature, .topP:
            return .float
        case .model, .systemPrompt, .stopSequences, .responseFormat, .reasoningEffort, .serviceTier:
            return .string
        }
    }

    var controlType: AiArgumentControlType {
        switch self {
        case .maxOutputTokens:
            return .stepper
        case .temperature, .topP:
            return .slider
        case .responseFormat:
            return .picker
        case .model, .systemPrompt, .stopSequences, .reasoningEffort, .serviceTier:
            return .textField
        }
    }

    var minValue: Double? {
        switch self {
        case .maxOutputTokens: return 1
        case .temperature, .topP: return 0
        default: return nil
        }
    }

    var maxValue: Double? {
        switch self {
        case .maxOutputTokens: return 200_000
        case .temperature: return 2
        case .topP: return 1
        default: return nil
        }
    }

    var step: Double? {
        switch self {
        case .maxOutputTokens: return 1
        case .temperature: return 0.1
        case .topP: return 0.05
        default: return nil
        }
    }

    var options: [String]? {
        switch self {
        case .responseFormat:
            return ["text", "json_object", "json_schema"]
        default:
            return nil
        }
    }

    var isEditableMappingParameter: Bool {
        switch self {
        case .model, .systemPrompt:
            return false
        default:
            return true
        }
    }
}

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
    var semanticParameterID: LLMApplicationParameterID
    var isEnabled: Bool
    var isRequired: Bool
    var encodingKind: ModelParameterEncodingKind
    var wireKey: String
    var structuredPreset: ModelParameterStructuredPreset?
    var defaultValue: JSONValue?

    init(
        endpointFamily: LLMEndpointFamily,
        semanticParameterID: LLMApplicationParameterID,
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

    static func materializeDefaults(on model: ModelItem, preserveCustomized: Bool = true) {
        let providerID = LLMProviderID(rawValue: model.providerID) ?? .customOpenAICompatible
        let endpointFamilies = model.endpointFamiliesRaw.compactMap { LLMEndpointFamily(rawValue: $0) }.filter { $0 != .models }
        for endpointFamily in endpointFamilies {
            materializeDefaults(on: model, endpointFamily: endpointFamily, providerID: providerID, preserveCustomized: preserveCustomized)
        }
    }

    static func resetDefaults(on model: ModelItem, endpointFamily: LLMEndpointFamily) {
        let providerID = LLMProviderID(rawValue: model.providerID) ?? .customOpenAICompatible
        materializeDefaults(on: model, endpointFamily: endpointFamily, providerID: providerID, preserveCustomized: false)
    }

    private static func materializeDefaults(
        on model: ModelItem,
        endpointFamily: LLMEndpointFamily,
        providerID: LLMProviderID,
        preserveCustomized: Bool
    ) {
        let defaults = defaults(providerID: providerID, endpointFamily: endpointFamily, modelID: model.modelID)
        for descriptor in defaults {
            if let existing = model.parameterMappings.first(where: {
                $0.endpointFamilyEnum == endpointFamily && $0.semanticParameterIDEnum == descriptor.semanticParameterID
            }) {
                if preserveCustomized && existing.isCustomized {
                    continue
                }
                existing.apply(descriptor, markCustomized: false)
            } else {
                model.parameterMappings.append(ModelParameterMappingItem(descriptor: descriptor))
            }
        }

        if !preserveCustomized {
            let defaultIDs = Set(defaults.map(\.semanticParameterID))
            model.parameterMappings.removeAll { mapping in
                mapping.endpointFamilyEnum == endpointFamily && !defaultIDs.contains(mapping.semanticParameterIDEnum)
            }
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
    ) -> [LLMApplicationParameterID: LLMParameterMappingDescriptor] {
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
        mappings: [LLMApplicationParameterID: LLMParameterMappingDescriptor]
    ) throws {
        for mapping in mappings.values where mapping.isEnabled {
            guard mapping.encodingKind == .scalarKey else { continue }
            guard let value = options.jsonValue(for: mapping.semanticParameterID) ?? mapping.defaultValue else {
                if mapping.isRequired {
                    throw LLMProviderError.unsupportedParameter("\(mapping.semanticParameterID.displayName) is required.")
                }
                continue
            }
            guard !mapping.wireKey.isEmpty else {
                throw LLMProviderError.unsupportedParameter("\(mapping.semanticParameterID.displayName) has no wire key.")
            }
            body[mapping.wireKey] = value
        }
    }
}

extension LLMGenerationOptions {
    func jsonValue(for parameterID: LLMApplicationParameterID) -> JSONValue? {
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
