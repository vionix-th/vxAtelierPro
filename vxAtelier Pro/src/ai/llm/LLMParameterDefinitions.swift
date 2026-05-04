import Foundation

enum LLMParameterID: String, Codable, CaseIterable, Identifiable {
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

    var definition: LLMParameterDefinition {
        LLMParameterDefinitionCatalog.definition(for: self)
    }

    var valueType: LLMParameterValueType { definition.valueType }
    var minValue: Double? { definition.minValue }
    var maxValue: Double? { definition.maxValue }
    var options: [String]? { definition.options }
    var isProviderMappable: Bool { definition.isProviderMappable }
}

public enum LLMParameterValueType: String, Codable {
    case string
    case integer
    case float
    case boolean
}

struct LLMParameterDefinition: Codable, Equatable, Identifiable {
    var id: LLMParameterID
    var valueType: LLMParameterValueType
    var minValue: Double?
    var maxValue: Double?
    var options: [String]?
    var isProviderMappable: Bool

    init(
        id: LLMParameterID,
        valueType: LLMParameterValueType,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        options: [String]? = nil,
        isProviderMappable: Bool = true
    ) {
        self.id = id
        self.valueType = valueType
        self.minValue = minValue
        self.maxValue = maxValue
        self.options = options
        self.isProviderMappable = isProviderMappable
    }
}

enum LLMParameterDefinitionCatalog {
    static func definition(for parameterID: LLMParameterID) -> LLMParameterDefinition {
        switch parameterID {
        case .model:
            return .init(id: parameterID, valueType: .string, isProviderMappable: false)
        case .systemPrompt:
            return .init(id: parameterID, valueType: .string, isProviderMappable: false)
        case .maxOutputTokens:
            return .init(id: parameterID, valueType: .integer, minValue: 1, maxValue: 200_000)
        case .temperature:
            return .init(id: parameterID, valueType: .float, minValue: 0, maxValue: 2)
        case .topP:
            return .init(id: parameterID, valueType: .float, minValue: 0, maxValue: 1)
        case .stopSequences:
            return .init(id: parameterID, valueType: .string)
        case .responseFormat:
            return .init(id: parameterID, valueType: .string, options: ["text", "json_object", "json_schema"])
        case .reasoningEffort:
            return .init(id: parameterID, valueType: .string)
        case .serviceTier:
            return .init(id: parameterID, valueType: .string)
        }
    }
}
