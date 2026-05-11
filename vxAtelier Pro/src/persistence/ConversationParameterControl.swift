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
    var isEnabled: Bool
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

        var controls = [
            control(
                for: .model,
                required: true,
                value: options.parameterValue(.model) ?? .string(modelID),
                isEnabled: true
            ),
            control(
                for: .systemPrompt,
                required: true,
                value: options.parameterValue(.systemPrompt),
                isEnabled: true
            )
        ]

        for descriptor in availability.values.sorted(by: {
            AiParameterPresentationCatalog.displayName(for: $0.semanticParameterID)
                < AiParameterPresentationCatalog.displayName(for: $1.semanticParameterID)
        }) {
            guard descriptor.isAvailable,
                  descriptor.semanticParameterID.isProviderMappable,
                  mappings[descriptor.semanticParameterID]?.encodingKind != .disabled else { continue }
            let value = options.parameterValue(descriptor.semanticParameterID) ?? descriptor.defaultValue
            controls.append(control(
                for: descriptor.semanticParameterID,
                required: descriptor.isRequired,
                value: value,
                isEnabled: LLMParameterAvailabilityResolver.isParameterSendable(
                    descriptor.semanticParameterID,
                    value: options.parameterValue(descriptor.semanticParameterID),
                    conversationPreference: options.parameterInclusionPreference(descriptor.semanticParameterID),
                    modelAvailability: descriptor
                )
            ))
        }

        return controls.sorted { lhs, rhs in
            if lhs.required != rhs.required { return lhs.required }
            if !lhs.required && !rhs.required && lhs.isEnabled != rhs.isEnabled {
                return lhs.isEnabled
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func control(
        for parameterID: LLMParameterID,
        required: Bool,
        value: JSONValue?,
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
            options: parameterID.options,
            value: value,
            isEnabled: isEnabled
        )
    }
}
