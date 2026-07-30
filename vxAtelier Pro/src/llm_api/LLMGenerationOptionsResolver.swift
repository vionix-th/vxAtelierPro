import Foundation

struct LLMResolvedGenerationParameters: Equatable {
    var options: LLMGenerationOptions
    var activeParameters: [LLMActiveParameter]
}

enum LLMGenerationOptionsResolver {
    static func isParameterActive(
        _ parameterID: LLMParameterID,
        conversationPreference: Bool?,
        profile: LLMParameterProfile?
    ) -> Bool {
        if profile?.isRequired == true { return true }
        if let conversationPreference { return conversationPreference }
        guard let profile, profile.support.state == .supported else { return false }
        return profile.isEnabledByDefault
    }

    static func resolve(
        options: LLMGenerationOptions,
        conversationPreferences: [String: Bool],
        providedParameterIDs: Set<LLMParameterID>? = nil,
        parameterProfiles: [LLMParameterID: LLMParameterProfile]
    ) throws -> LLMResolvedGenerationParameters {
        var resolvedOptions = options
        var activeParameters: [LLMActiveParameter] = []

        for (rawID, isEnabled) in conversationPreferences where isEnabled {
            guard let parameterID = LLMParameterID(rawValue: rawID) else { continue }
            guard parameterProfiles[parameterID]?.support.state == .supported else {
                throw LLMProviderError.invalidConfiguration(
                    "\(parameterID.rawValue) is enabled but unavailable for the selected model and API."
                )
            }
        }

        for parameterID in LLMParameterID.allCases where parameterProfiles[parameterID] != nil {
            let profile = parameterProfiles[parameterID]
            let isActive = isParameterActive(
                parameterID,
                conversationPreference: conversationPreferences[parameterID.rawValue],
                profile: profile
            )
            guard isActive else { continue }
            let hasProvidedValue = providedParameterIDs?.contains(parameterID)
                ?? (options.jsonValue(for: parameterID) != nil)
            if !hasProvidedValue, let defaultValue = profile?.defaultValue {
                resolvedOptions.setSemanticValue(defaultValue, for: parameterID)
            }
            guard profile?.support.state == .supported, let mapping = profile?.mapping else {
                throw LLMProviderError.invalidConfiguration(
                    "\(parameterID.rawValue) has no valid definition for the selected model and API."
                )
            }
            activeParameters.append(LLMActiveParameter(parameterID: parameterID, mapping: mapping))
        }

        return LLMResolvedGenerationParameters(
            options: resolvedOptions,
            activeParameters: activeParameters
        )
    }
}

extension LLMGenerationOptions {
    mutating func setSemanticValue(_ value: JSONValue, for parameterID: LLMParameterID) {
        switch parameterID {
        case .model:
            modelID = value.stringValue
        case .systemPrompt:
            systemPrompt = value.stringValue ?? ""
        case .maxOutputTokens:
            maxOutputTokens = value.integerValue
        case .topK:
            topK = value.integerValue
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
        case .reasoningSummary:
            reasoningSummary = value.stringValue
        case .reasoningBudgetTokens:
            reasoningBudgetTokens = value.integerValue
        case .serviceTier:
            serviceTier = value.stringValue
        case .textVerbosity:
            textVerbosity = value.stringValue
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
             .frequencyPenalty,
             .presencePenalty,
             .logitBias,
             .seed,
             .user,
             .safetyIdentifier:
            providerSpecificOptions[parameterID.rawValue] = value
        }
    }
}
