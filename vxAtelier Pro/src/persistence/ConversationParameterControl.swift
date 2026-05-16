import Foundation

/// Non-persistent parameter row rendered from typed conversation options and model availability.
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
    var isAvailable: Bool
    var isMapped: Bool
    var isEnabled: Bool

    var canToggleEnabled: Bool {
        isAvailable && isMapped && !required
    }

    var isValueEditable: Bool {
        isAvailable && isMapped
    }
}

enum ConversationParameterProjection {
    @MainActor
    static func controls(
        for options: ConversationOptions,
        apiConfiguration: APIConfigurationItem?
    ) -> [ConversationParameterControl] {
        guard let apiConfiguration else { return [] }

        let adapterID = apiConfiguration.defaultAdapterIDEnum
        let modelID = options.selectedModelID
            ?? apiConfiguration.defaultModelID
            ?? ""
        let model = apiConfiguration.models.first { $0.modelID == modelID }
        let mappings = LLMParameterMappingResolver.resolve(
            adapterID: adapterID,
            mappings: model?.parameterMappings.map(\.descriptor) ?? []
        )
        let availability = LLMParameterAvailabilityMappingResolver.resolve(
            adapterID: adapterID,
            availability: model?.parameterAvailability.map(\.descriptor) ?? []
        )

        var controls: [ConversationParameterControl] = []
        for parameterID in LLMParameterID.allCases {
            let descriptor = availability[parameterID]
            let mapping = mappings[parameterID]
            let isProviderMappable = parameterID.isProviderMappable
            let isAvailable = !isProviderMappable || descriptor?.isAvailable == true
            let isMapped = !isProviderMappable || (mapping != nil && mapping?.encodingKind != .disabled)
            let required = !isProviderMappable || descriptor?.isRequired == true
            let value = options.parameterValue(parameterID)
                ?? descriptor?.defaultValue
                ?? (parameterID == .model ? .string(modelID) : nil)
            let isEnabled: Bool
            if !isAvailable || !isMapped {
                isEnabled = false
            } else if required {
                isEnabled = true
            } else if let descriptor {
                isEnabled = LLMParameterAvailabilityResolver.isParameterSendable(
                    parameterID,
                    value: options.parameterValue(parameterID),
                    conversationPreference: options.parameterInclusionPreference(parameterID),
                    modelAvailability: descriptor
                )
            } else {
                isEnabled = options.isParameterEnabled(parameterID)
            }
            controls.append(control(
                for: parameterID,
                required: required,
                options: descriptor?.options,
                value: value,
                isAvailable: isAvailable,
                isMapped: isMapped,
                isEnabled: isEnabled
            ))
        }

        return controls.sorted { lhs, rhs in
            let lhsGroup = sortGroup(for: lhs)
            let rhsGroup = sortGroup(for: rhs)
            if lhsGroup != rhsGroup {
                return lhsGroup < rhsGroup
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func sortGroup(for control: ConversationParameterControl) -> Int {
        if control.isEnabled { return 0 }
        if control.isAvailable && control.isMapped { return 1 }
        return 2
    }

    private static func control(
        for parameterID: LLMParameterID,
        required: Bool,
        options: [String]?,
        value: JSONValue?,
        isAvailable: Bool,
        isMapped: Bool,
        isEnabled: Bool
    ) -> ConversationParameterControl {
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
            options: options ?? parameterID.options,
            value: value,
            isAvailable: isAvailable,
            isMapped: isMapped,
            isEnabled: isEnabled
        )
    }
}
