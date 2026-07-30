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
    var isSupported: Bool
    var isEnabled: Bool

    var canToggleEnabled: Bool {
        !required && (isSupported || isEnabled)
    }

    var isValueEditable: Bool {
        isSupported && isEnabled
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

        return LLMParameterID.allCases.compactMap { parameterID in
            let profile = parameterProfiles[parameterID]
            let isSupported = profile?.support.state == .supported
            let isRetainedSelection = options.parameterInclusionPreference(parameterID) == true
            guard isSupported || isRetainedSelection else { return nil }
            let required = profile?.isRequired == true
            let value = options.parameterValue(parameterID)
                ?? profile?.defaultValue
                ?? (parameterID == .model ? .string(modelID) : nil)
            let isEnabled = required || LLMGenerationOptionsResolver.isParameterActive(
                parameterID,
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
                isSupported: isSupported,
                isEnabled: isEnabled
            )
        }
        .sorted { lhs, rhs in
            let lhsGroup = lhs.isEnabled ? 0 : (lhs.isSupported ? 1 : 2)
            let rhsGroup = rhs.isEnabled ? 0 : (rhs.isSupported ? 1 : 2)
            if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
