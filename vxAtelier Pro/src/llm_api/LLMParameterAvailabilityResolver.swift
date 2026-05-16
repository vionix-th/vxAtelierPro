import Foundation

/// Model-level availability and enabled state for one semantic parameter.
struct LLMParameterAvailabilityDescriptor: Codable, Equatable, Identifiable {
    /// Combines adapter and semantic parameter so one model can store per-adapter availability.
    var id: String { "\(adapterID.rawValue):\(semanticParameterID.rawValue)" }
    var adapterID: LLMAdapterID
    var semanticParameterID: LLMParameterID
    var isAvailable: Bool
    var isRequired: Bool
    var isEnabled: Bool
    var defaultValue: JSONValue?

    /// Creates model-level sendability metadata for a semantic parameter at one adapter.
    init(
        adapterID: LLMAdapterID,
        semanticParameterID: LLMParameterID,
        isAvailable: Bool = true,
        isRequired: Bool = false,
        isEnabled: Bool = false,
        defaultValue: JSONValue? = nil
    ) {
        self.adapterID = adapterID
        self.semanticParameterID = semanticParameterID
        self.isAvailable = isAvailable
        self.isRequired = isRequired
        self.isEnabled = isEnabled
        self.defaultValue = defaultValue
    }
}

/// Default parameter availability loaded from bundled LLM defaults.
enum LLMParameterAvailabilityCatalog {
    /// Returns default availability for a provider, adapter, and model.
    static func defaults(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String
    ) -> [LLMParameterAvailabilityDescriptor] {
        LLMDefaultsCatalog.bundled.parameterAvailability(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID
        )
    }
}

/// Resolves persisted model-specific parameter availability.
struct LLMParameterAvailabilityMappingResolver {
    /// Returns availability keyed by semantic parameter for one adapter.
    static func resolve(
        adapterID: LLMAdapterID,
        availability: [LLMParameterAvailabilityDescriptor]
    ) -> [LLMParameterID: LLMParameterAvailabilityDescriptor] {
        Dictionary(uniqueKeysWithValues: availability
            .filter { $0.adapterID == adapterID }
            .map { ($0.semanticParameterID, $0) })
    }
}

/// Resolves model-specific semantic parameter availability before provider wire encoding.
enum LLMParameterAvailabilityResolver {
    /// Returns true when a semantic parameter should remain in the provider-neutral request.
    static func isParameterSendable(
        _ parameterID: LLMParameterID,
        value: JSONValue?,
        conversationPreference: Bool?,
        modelAvailability: LLMParameterAvailabilityDescriptor?
    ) -> Bool {
        guard parameterID.isProviderMappable else { return true }
        guard let availability = modelAvailability else { return false }
        guard availability.isAvailable else { return false }
        if availability.isRequired { return true }
        if let conversationPreference { return conversationPreference }
        return availability.isEnabled || value != nil || availability.defaultValue != nil
    }

    /// Returns provider-neutral options after model availability and conversation preferences are applied.
    static func resolvedOptions(
        from options: LLMGenerationOptions,
        conversationPreferences: [String: Bool],
        modelAvailability: [LLMParameterID: LLMParameterAvailabilityDescriptor]
    ) -> LLMGenerationOptions {
        var resolved = options
        let sendableAvailability = sendableModelAvailability(
            for: options,
            conversationPreferences: conversationPreferences,
            modelAvailability: modelAvailability
        )
        for parameterID in LLMParameterID.allCases where parameterID.isProviderMappable {
            guard let availability = sendableAvailability[parameterID] else {
                resolved.removeSemanticValue(for: parameterID)
                continue
            }
            if resolved.jsonValue(for: parameterID) == nil, let defaultValue = availability.defaultValue {
                resolved.setSemanticValue(defaultValue, for: parameterID)
            }
        }
        return resolved
    }

    /// Returns model availability only for semantic parameters that may affect this request.
    static func sendableModelAvailability(
        for options: LLMGenerationOptions,
        conversationPreferences: [String: Bool],
        modelAvailability: [LLMParameterID: LLMParameterAvailabilityDescriptor]
    ) -> [LLMParameterID: LLMParameterAvailabilityDescriptor] {
        modelAvailability.filter { entry in
            isParameterSendable(
                entry.key,
                value: options.jsonValue(for: entry.key),
                conversationPreference: conversationPreferences[entry.key.rawValue],
                modelAvailability: entry.value
            )
        }
    }
}

private extension LLMGenerationOptions {
    /// Removes a provider-mappable semantic value after availability has been resolved.
    mutating func removeSemanticValue(for parameterID: LLMParameterID) {
        switch parameterID {
        case .model, .systemPrompt:
            break
        case .maxOutputTokens:
            maxOutputTokens = nil
        case .temperature:
            temperature = nil
        case .topP:
            topP = nil
        case .stopSequences:
            stop = []
        case .responseFormat:
            responseFormat = .text
        case .reasoningEffort:
            reasoning = nil
        case .serviceTier:
            serviceTier = nil
        case .stream:
            streamMode = .disabled
        case .store,
             .toolChoice,
             .parallelToolCalls,
             .promptCacheKey,
             .previousResponseID,
             .include,
             .textVerbosity,
             .frequencyPenalty,
             .presencePenalty,
             .logitBias,
             .seed,
             .user,
             .safetyIdentifier,
             .reasoningSummary:
            providerExtras.removeValue(forKey: parameterID.rawValue)
        }
    }

    /// Applies a model-level default value before provider-specific request encoding.
    mutating func setSemanticValue(_ value: JSONValue, for parameterID: LLMParameterID) {
        switch parameterID {
        case .model:
            modelID = value.stringValue
        case .systemPrompt:
            systemPrompt = value.stringValue ?? ""
        case .maxOutputTokens:
            maxOutputTokens = value.integerValue
        case .temperature:
            temperature = value.doubleValue
        case .topP:
            topP = value.doubleValue
        case .stopSequences:
            if let array = value.arrayValue {
                stop = array.compactMap(\.stringValue)
            } else if let string = value.stringValue, !string.isEmpty {
                stop = [string]
            }
        case .responseFormat:
            responseFormat = LLMGenerationOptions.ResponseFormat.fromSemanticRawValue(value.stringValue ?? "text")
        case .reasoningEffort:
            reasoning = value.stringValue
        case .serviceTier:
            serviceTier = value.stringValue
        case .stream:
            if let bool = value.boolValue {
                streamMode = bool ? .enabled : .disabled
            } else if let string = value.stringValue {
                streamMode = LLMGenerationOptions.StreamMode(rawValue: string) ?? .disabled
            }
        case .store,
             .toolChoice,
             .parallelToolCalls,
             .promptCacheKey,
             .previousResponseID,
             .include,
             .textVerbosity,
             .frequencyPenalty,
             .presencePenalty,
             .logitBias,
             .seed,
             .user,
             .safetyIdentifier,
             .reasoningSummary:
            providerExtras[parameterID.rawValue] = value
        }
    }
}
