import Foundation
import SwiftData

/// Non-persistent parameter row rendered from typed conversation options and model mappings.
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
        apiConfiguration: APIConfigurationItem?,
        modelContext: ModelContext?,
        resolver: LLMModelDescriptorResolver = LLMModelDescriptorResolver()
    ) -> [ConversationParameterControl] {
        guard let apiConfiguration else { return [] }

        let providerID = apiConfiguration.providerIDEnum
        let endpointFamily = options.endpointOverrideFamily ?? apiConfiguration.defaultEndpointFamilyEnum
        let modelID = options.modelOverride
            ?? resolver.defaultModelID(for: providerID, apiConfiguration: apiConfiguration)
            ?? ""
        let descriptor = try? resolver.descriptor(
            for: modelID,
            providerID: providerID,
            apiConfiguration: apiConfiguration,
            modelContext: modelContext,
            endpointFamilies: [endpointFamily]
        )
        let mappings = LLMParameterMappingResolver.resolve(
            providerID: providerID,
            endpointFamily: endpointFamily,
            modelID: modelID,
            modelDescriptor: descriptor
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

        for mapping in mappings.values.sorted(by: {
            AiParameterPresentationCatalog.displayName(for: $0.semanticParameterID)
                < AiParameterPresentationCatalog.displayName(for: $1.semanticParameterID)
        }) {
            guard mapping.isEnabled, mapping.semanticParameterID.isProviderMappable else { continue }
            let value = options.parameterValue(mapping.semanticParameterID) ?? mapping.defaultValue
            controls.append(control(
                for: mapping.semanticParameterID,
                required: mapping.isRequired,
                value: value,
                isEnabled: options.isParameterEnabled(mapping.semanticParameterID, mapping: mapping)
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
