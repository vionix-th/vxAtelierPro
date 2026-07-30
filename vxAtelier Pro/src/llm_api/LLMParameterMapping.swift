import Foundation

/// Encoding strategy for a semantic parameter in a provider request body.
enum LLMParameterEncodingKind: String, Codable, CaseIterable, Identifiable {
    case adapter
    case key
    case preset

    /// Exposes the raw encoding key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing encoding name for model mapping controls.
    var displayName: String {
        switch self {
        case .adapter: return "Adapter"
        case .key: return "Key"
        case .preset: return "Preset"
        }
    }
}

/// Known structured encodings that cannot be represented by a scalar wire key.
enum LLMParameterStructuredPreset: String, Codable, CaseIterable, Identifiable {
    case openAIChatResponseFormat
    case openAIResponsesTextFormat
    case openAIResponsesReasoning
    case openAIResponsesTextVerbosity
    case openAIResponsesReasoningSummary
    case openRouterReasoning
    case anthropicThinking

    /// Exposes the raw preset key as the SwiftUI identity.
    var id: String { rawValue }

    /// Human-facing preset name for model mapping controls.
    var displayName: String {
        switch self {
        case .openAIChatResponseFormat: return "OpenAI Chat Response Format"
        case .openAIResponsesTextFormat: return "OpenAI Responses Text Format"
        case .openAIResponsesReasoning: return "OpenAI Responses Reasoning"
        case .openAIResponsesTextVerbosity: return "OpenAI Responses Text Verbosity"
        case .openAIResponsesReasoningSummary: return "OpenAI Responses Reasoning Summary"
        case .openRouterReasoning: return "OpenRouter Reasoning"
        case .anthropicThinking: return "Anthropic Thinking"
        }
    }

    func supports(_ adapterID: LLMAdapterID) -> Bool {
        switch (self, adapterID) {
        case (.openAIChatResponseFormat, .openAIChatCompletions),
             (.openAIChatResponseFormat, .openAIChatCompletionsLegacy),
             (.openAIChatResponseFormat, .openRouterChatCompletions),
             (.openAIResponsesTextFormat, .openAIResponses),
             (.openAIResponsesReasoning, .openAIResponses),
             (.openAIResponsesTextVerbosity, .openAIResponses),
             (.openAIResponsesReasoningSummary, .openAIResponses),
             (.openRouterReasoning, .openRouterChatCompletions),
             (.anthropicThinking, .anthropicMessages):
            return true
        default:
            return false
        }
    }
}

extension LLMAdapterID {
    var supportsKeyParameterMappings: Bool {
        self != .foundationModels
    }

    func ownsEncoding(of parameterID: LLMParameterID) -> Bool {
        switch self {
        case .foundationModels:
            return [.model, .systemPrompt, .stream, .temperature, .maxOutputTokens]
                .contains(parameterID)
        case .openAIResponses,
             .openAIChatCompletions,
             .openAIChatCompletionsLegacy,
             .openRouterChatCompletions,
             .anthropicMessages:
            return [.model, .systemPrompt, .stream].contains(parameterID)
        }
    }
}

/// Mapping from one semantic parameter to one adapter-specific wire encoding.
struct LLMParameterMapping: Codable, Equatable, Identifiable {
    /// Combines adapter and semantic parameter so one model can store per-adapter mappings.
    var id: String { "\(adapterID.rawValue):\(parameterID.rawValue)" }
    var adapterID: LLMAdapterID
    var parameterID: LLMParameterID
    var encodingKind: LLMParameterEncodingKind
    var wireKey: String
    var structuredPreset: LLMParameterStructuredPreset?

    /// Creates a provider mapping for a semantic parameter at one adapter.
    init(
        adapterID: LLMAdapterID,
        parameterID: LLMParameterID,
        encodingKind: LLMParameterEncodingKind = .key,
        wireKey: String = "",
        structuredPreset: LLMParameterStructuredPreset? = nil
    ) {
        self.adapterID = adapterID
        self.parameterID = parameterID
        self.encodingKind = encodingKind
        self.wireKey = wireKey
        self.structuredPreset = structuredPreset
    }
}

struct LLMActiveParameter: Codable, Equatable, Identifiable {
    var id: LLMParameterID { parameterID }
    var parameterID: LLMParameterID
    var mapping: LLMParameterMapping
}

/// Encodes scalar semantic parameters into a provider request body.
enum LLMParameterWireEncoder {
    /// Applies only key mappings; adapter and preset mappings are adapter-specific.
    static func applyScalarOptions(
        _ options: LLMGenerationOptions,
        to body: inout [String: JSONValue],
        parameters: [LLMActiveParameter]
    ) throws {
        for parameter in parameters {
            let mapping = parameter.mapping
            guard mapping.encodingKind == .key else { continue }
            guard let value = options.jsonValue(for: mapping.parameterID) else {
                throw LLMProviderError.requestEncoding(
                    "Active parameter \(mapping.parameterID.rawValue) has no value."
                )
            }
            guard !mapping.wireKey.isEmpty else {
                throw LLMProviderError.requestEncoding("\(mapping.parameterID.rawValue) has no wire key.")
            }
            guard body[mapping.wireKey] == nil else {
                throw LLMProviderError.requestEncoding(
                    "\(mapping.parameterID.rawValue) maps to reserved or duplicate key \(mapping.wireKey)."
                )
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
        case .topK:
            return topK.map { .integer($0) }
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
        case .reasoningSummary:
            return reasoningSummary.flatMap { $0.isEmpty ? nil : .string($0) }
        case .reasoningBudgetTokens:
            return reasoningBudgetTokens.map { .integer($0) }
        case .serviceTier:
            return serviceTier.flatMap { $0.isEmpty ? nil : .string($0) }
        case .textVerbosity:
            return textVerbosity.flatMap { $0.isEmpty ? nil : .string($0) }
        case .stream:
            switch streamMode {
            case .enabled:
                return .boolean(true)
            case .disabled:
                return .boolean(false)
            }
        case .store,
             .toolChoice,
             .parallelToolCalls,
             .promptCacheKey,
             .previousResponseID,
             .include,
             .frequencyPenalty,
             .presencePenalty,
             .logitBias,
             .seed,
             .user,
             .safetyIdentifier:
            return providerSpecificOptions[parameterID.rawValue]
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
