import Foundation

/// Semantic generation parameter independent of provider wire keys.
enum LLMParameterID: String, Codable, CaseIterable, Identifiable {
    case model
    case systemPrompt = "system_prompt"
    case maxOutputTokens = "max_output_tokens"
    case temperature
    case topP = "top_p"
    case stopSequences = "stop_sequences"
    case responseFormat = "response_format"
    case reasoningEffort = "reasoning_effort"
    case reasoningSummary = "reasoning_summary"
    case reasoningBudgetTokens = "reasoning_budget_tokens"
    case serviceTier = "service_tier"
    case topK = "top_k"
    case stream
    case store
    case toolChoice = "tool_choice"
    case parallelToolCalls = "parallel_tool_calls"
    case promptCacheKey = "prompt_cache_key"
    case previousResponseID = "previous_response_id"
    case include
    case textVerbosity = "text_verbosity"
    case frequencyPenalty = "frequency_penalty"
    case presencePenalty = "presence_penalty"
    case logitBias = "logit_bias"
    case seed
    case user
    case safetyIdentifier = "safety_identifier"

    /// Exposes the semantic parameter key as the SwiftUI identity.
    var id: String { rawValue }

    /// Built-in metadata for validation and settings controls.
    var definition: LLMParameterDefinition {
        LLMParameterDefinitionCatalog.definition(for: self)
    }

    /// Expected primitive value class for this parameter.
    var valueType: LLMParameterValueType { definition.valueType }
    /// Inclusive lower bound for numeric parameters.
    var minValue: Double? { definition.minValue }
    /// Inclusive upper bound for numeric parameters.
    var maxValue: Double? { definition.maxValue }
    /// Allowed values for enumerated string parameters.
    var options: [String]? { definition.options }
    /// Indicates whether provider adapters may map this parameter onto a wire field.
    var isProviderMappable: Bool { definition.isProviderMappable }
}

/// Primitive value class used to render and validate parameter controls.
public enum LLMParameterValueType: String, Codable {
    case string
    case integer
    case float
    case boolean
}

/// Metadata describing valid values for a semantic generation parameter.
struct LLMParameterDefinition: Codable, Equatable, Identifiable {
    var id: LLMParameterID
    var valueType: LLMParameterValueType
    var minValue: Double?
    var maxValue: Double?
    var options: [String]?
    var isProviderMappable: Bool

    /// Creates semantic parameter metadata used by validation and UI controls.
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

/// Built-in semantic parameter definitions.
enum LLMParameterDefinitionCatalog {
    /// Returns validation metadata for a semantic generation parameter.
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
            return .init(
                id: parameterID,
                valueType: .string,
                options: ["none", "minimal", "low", "medium", "high", "xhigh"]
            )
        case .reasoningSummary:
            return .init(
                id: parameterID,
                valueType: .string,
                options: ["auto", "concise", "detailed"]
            )
        case .reasoningBudgetTokens:
            return .init(id: parameterID, valueType: .integer, minValue: 1024, maxValue: 200_000)
        case .serviceTier:
            return .init(
                id: parameterID,
                valueType: .string,
                options: ["auto", "default", "flex", "priority"]
            )
        case .topK:
            return .init(id: parameterID, valueType: .integer, minValue: 0)
        case .stream, .store, .parallelToolCalls:
            return .init(id: parameterID, valueType: .boolean)
        case .toolChoice, .promptCacheKey, .previousResponseID, .include, .logitBias, .user, .safetyIdentifier:
            return .init(id: parameterID, valueType: .string)
        case .textVerbosity:
            return .init(id: parameterID, valueType: .string, options: ["low", "medium", "high"])
        case .frequencyPenalty, .presencePenalty:
            return .init(id: parameterID, valueType: .float, minValue: -2, maxValue: 2)
        case .seed:
            return .init(id: parameterID, valueType: .integer)
        }
    }
}
