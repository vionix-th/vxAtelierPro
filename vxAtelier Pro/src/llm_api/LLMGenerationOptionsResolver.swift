import Foundation

struct LLMParameterDefaults: Codable, Equatable, Identifiable {
    var id: String { "\(adapterID.rawValue):\(parameterID.rawValue)" }
    var adapterID: LLMAdapterID
    var parameterID: LLMParameterID
    var support: LLMSupportState
    var isRequired: Bool
    var isEnabledByDefault: Bool
    var defaultValue: JSONValue?
    var options: [String]?
}

struct LLMResolvedGenerationParameters: Equatable {
    var options: LLMGenerationOptions
    var activeParameterIDs: Set<LLMParameterID>
    var mappings: [LLMParameterMapping]
}

enum LLMGenerationOptionsResolver {
    static func isParameterActive(
        _ parameterID: LLMParameterID,
        value: JSONValue?,
        conversationPreference: Bool?,
        contract: LLMResolvedParameterContract?
    ) -> Bool {
        guard parameterID.isProviderMappable else { return true }
        if contract?.isRequired == true { return true }
        if let conversationPreference { return conversationPreference }
        guard let contract else { return value != nil }
        return contract.isEnabledByDefault
            || value != nil
            || contract.defaultValue != nil
    }

    static func resolve(
        options: LLMGenerationOptions,
        conversationPreferences: [String: Bool],
        parameterContracts: [LLMParameterID: LLMResolvedParameterContract]
    ) -> LLMResolvedGenerationParameters {
        var resolvedOptions = options
        var activeParameterIDs = Set<LLMParameterID>()
        var mappings: [LLMParameterMapping] = []

        for parameterID in LLMParameterID.allCases where parameterID.isProviderMappable {
            let contract = parameterContracts[parameterID]
            let isActive = isParameterActive(
                parameterID,
                value: options.jsonValue(for: parameterID),
                conversationPreference: conversationPreferences[parameterID.rawValue],
                contract: contract
            )
            guard isActive else { continue }
            activeParameterIDs.insert(parameterID)
            if resolvedOptions.jsonValue(for: parameterID) == nil, let defaultValue = contract?.defaultValue {
                resolvedOptions.setSemanticValue(defaultValue, for: parameterID)
            }
            if let mapping = contract?.mapping {
                mappings.append(mapping)
            }
        }

        return LLMResolvedGenerationParameters(
            options: resolvedOptions,
            activeParameterIDs: activeParameterIDs,
            mappings: mappings
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
