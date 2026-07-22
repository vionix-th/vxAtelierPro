import Foundation

struct ConversationParameterControl: Identifiable, Equatable {
    var id: LLMParameterID { parameterID }
    var parameterID: LLMParameterID
    var displayName: String
    var description: String
    var required: Bool
    var valueType: LLMParameterValueType
    var controlType: AiArgumentControlType
    var minValue: Double?
    var maxValue: Double?
    var step: Double?
    var options: [String]?
    var value: JSONValue?
    var support: LLMSupport
    var isMapped: Bool
    var isEnabled: Bool

    var canToggleEnabled: Bool {
        !required && (isMapped || isEnabled)
    }

    var isValueEditable: Bool {
        isMapped && isEnabled
    }
}

enum ConversationParameterProjection {
    @MainActor
    static func controls(
        for options: ConversationOptions,
        apiConfiguration: APIConfigurationItem?
    ) -> [ConversationParameterControl] {
        guard let apiConfiguration else { return [] }

        let modelID = options.selectedModelID ?? apiConfiguration.defaultModelID ?? ""
        let model = apiConfiguration.models.first { $0.modelID == modelID }
        let parameterProfiles = model?.modelProfile.parameters ?? [:]

        return LLMParameterID.allCases.map { parameterID in
            let profile = parameterProfiles[parameterID]
            let isProviderMappable = parameterID.isProviderMappable
            let mapping = profile?.mapping
            let isDirectlyEncodable = parameterID == .stream && (try? LLMProviderRegistry.shared.resolveAdapter(
                for: apiConfiguration.defaultAdapterIDEnum,
                providerID: apiConfiguration.providerIDEnum
            )) != nil
            let isMapped = !isProviderMappable
                || isDirectlyEncodable
                || (mapping != nil && mapping?.encodingKind != .disabled)
            let required = !isProviderMappable || profile?.isRequired == true
            let value = options.parameterValue(parameterID)
                ?? profile?.defaultValue
                ?? (parameterID == .model ? .string(modelID) : nil)
            let isEnabled = required || LLMGenerationOptionsResolver.isParameterActive(
                parameterID,
                value: options.parameterValue(parameterID),
                conversationPreference: options.parameterInclusionPreference(parameterID),
                profile: profile
            )
            let presentation = AiParameterPresentationCatalog.presentation(for: parameterID)
            return ConversationParameterControl(
                parameterID: parameterID,
                displayName: presentation.displayName,
                description: presentation.description,
                required: required,
                valueType: parameterID.valueType,
                controlType: presentation.controlType,
                minValue: parameterID.minValue,
                maxValue: parameterID.maxValue,
                step: presentation.step,
                options: profile?.options ?? parameterID.options,
                value: value,
                support: profile?.support ?? LLMSupport(state: .unknown, source: .fallback),
                isMapped: isMapped,
                isEnabled: isEnabled
            )
        }
        .sorted { lhs, rhs in
            let lhsGroup = lhs.isEnabled ? 0 : (lhs.isMapped ? 1 : 2)
            let rhsGroup = rhs.isEnabled ? 0 : (rhs.isMapped ? 1 : 2)
            if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
