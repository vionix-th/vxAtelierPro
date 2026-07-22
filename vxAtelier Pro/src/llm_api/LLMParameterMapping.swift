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
        encodingKind: LLMParameterEncodingKind = .scalarKey,
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

/// Default parameter mappings loaded from bundled LLM defaults.
enum LLMParameterMappingCatalog {
    /// Returns default mappings for a provider, adapter, and model.
    static func defaults(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String
    ) -> [LLMParameterMapping] {
        LLMDefaultsCatalog.bundled.parameterMappings(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID
        )
    }
}

/// Resolves persisted model-specific mappings.
struct LLMParameterMappingIndex {
    /// Returns active mappings keyed by semantic parameter.
    static func resolve(
        adapterID: LLMAdapterID,
        mappings: [LLMParameterMapping]
    ) -> [LLMParameterID: LLMParameterMapping] {
        Dictionary(uniqueKeysWithValues: mappings
            .filter { $0.adapterID == adapterID }
            .map { ($0.parameterID, $0) })
    }

    static func requireEncodableMappings(
        activeParameterIDs: Set<LLMParameterID>,
        mappings: [LLMParameterID: LLMParameterMapping],
        directlyEncodedParameterIDs: Set<LLMParameterID> = [.stream]
    ) throws -> [LLMParameterID: LLMParameterMapping] {
        for parameterID in activeParameterIDs.subtracting(directlyEncodedParameterIDs) {
            guard let mapping = mappings[parameterID], mapping.encodingKind != .disabled else {
                throw LLMProviderError.requestEncoding(
                    "No active wire mapping for \(parameterID.rawValue)."
                )
            }
        }
        return mappings.filter { activeParameterIDs.contains($0.key) }
    }
}

/// Encodes scalar semantic parameters into a provider request body.
enum LLMParameterWireEncoder {
    /// Applies only scalar-key mappings; structured presets are adapter-specific.
    static func applyScalarOptions(
        _ options: LLMGenerationOptions,
        to body: inout [String: JSONValue],
        mappings: [LLMParameterID: LLMParameterMapping],
        activeParameterIDs: Set<LLMParameterID>
    ) throws {
        let activeMappings = try LLMParameterMappingIndex.requireEncodableMappings(
            activeParameterIDs: activeParameterIDs,
            mappings: mappings
        )
        for mapping in activeMappings.values {
            guard let value = options.jsonValue(for: mapping.parameterID) else {
                throw LLMProviderError.requestEncoding(
                    "Active parameter \(mapping.parameterID.rawValue) has no value."
                )
            }
            guard mapping.encodingKind == .scalarKey else { continue }
            guard !mapping.wireKey.isEmpty else {
                throw LLMProviderError.requestEncoding("\(mapping.parameterID.rawValue) has no wire key.")
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
