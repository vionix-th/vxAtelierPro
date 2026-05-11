import Foundation
import SwiftData

// MARK: - Model Export

struct ModelExportData: Codable {
    let name: String
    let contextSize: Int
    let modelID: String?
    let displayName: String?
    let capabilities: [String]?
    let rawMetadataJSON: String?
    let parameterMappings: [ModelParameterMappingExportData]?
    let parameterAvailability: [ModelParameterAvailabilityExportData]?
    let apiConfigurationName: String?
    let apiConfigurationProviderID: String?
    let apiConfigurationBaseURL: String?
    
    init(_ model: ModelItem) {
        self.name = model.name
        self.contextSize = model.contextSize
        self.modelID = model.modelID
        self.displayName = model.displayName
        self.capabilities = model.capabilitiesRaw
        self.rawMetadataJSON = model.rawMetadataJSON
        self.parameterMappings = model.parameterMappings.map { ModelParameterMappingExportData($0) }
        self.parameterAvailability = model.parameterAvailability.map { ModelParameterAvailabilityExportData($0) }
        self.apiConfigurationName = model.apiConfiguration?.name
        self.apiConfigurationProviderID = model.apiConfiguration?.providerID
        self.apiConfigurationBaseURL = model.apiConfiguration?.baseURL
    }
    
    func toDataItem(apiConfigurations: [APIConfigurationItem] = []) -> ModelItem {
        let apiConfiguration = apiConfigurations.first {
            $0.name == apiConfigurationName
                && $0.providerID == apiConfigurationProviderID
                && $0.baseURL == apiConfigurationBaseURL
        }
        let model = ModelItem(
            modelID: modelID ?? name,
            contextSize: contextSize,
            apiConfiguration: apiConfiguration
        )
        model.displayName = displayName ?? name
        let defaultCandidate = LLMModelDescriptorResolver().catalogDescriptor(
            for: model.modelID,
            providerID: apiConfiguration?.providerIDEnum ?? .customOpenAICompatible
        )
        model.capabilitiesRaw = defaultCandidate.capabilities.map(\.rawValue)
        if let capabilities { model.capabilitiesRaw = capabilities }
        model.rawMetadataJSON = rawMetadataJSON
        model.parameterMappings = parameterMappings?.map { $0.toDataItem() } ?? []
        model.parameterAvailability = parameterAvailability?.map { $0.toDataItem() } ?? []
        model.materializeDefaultParameterMappings(preserveCustomized: true)
        model.materializeDefaultParameterAvailability(preserveCustomized: true)
        return model
    }
}

struct ModelParameterMappingExportData: Codable {
    let adapterIDRaw: String
    let semanticParameterID: String
    let encodingKindRaw: String
    let wireKey: String
    let structuredPresetRaw: String?
    let displayName: String
    let paramDescription: String
    let valueType: String
    let controlType: String
    let minValue: Double?
    let maxValue: Double?
    let step: Double?
    let options: [String]?
    let isCustomized: Bool

    init(_ mapping: ModelParameterMappingItem) {
        adapterIDRaw = mapping.adapterIDRaw
        semanticParameterID = mapping.semanticParameterID
        encodingKindRaw = mapping.encodingKindRaw
        wireKey = mapping.wireKey
        structuredPresetRaw = mapping.structuredPresetRaw
        displayName = mapping.displayName
        paramDescription = mapping.paramDescription
        valueType = mapping.valueType
        controlType = mapping.controlType
        minValue = mapping.minValue
        maxValue = mapping.maxValue
        step = mapping.step
        options = mapping.options
        isCustomized = mapping.isCustomized
    }

    func toDataItem() -> ModelParameterMappingItem {
        let mapping = ModelParameterMappingItem(
            adapterID: LLMAdapterID(rawValue: adapterIDRaw) ?? .openAIChatCompletions,
            semanticParameterID: LLMParameterID(rawValue: semanticParameterID) ?? .maxOutputTokens,
            encodingKind: LLMParameterEncodingKind(rawValue: encodingKindRaw) ?? .scalarKey,
            wireKey: wireKey,
            structuredPreset: structuredPresetRaw.flatMap(LLMParameterStructuredPreset.init(rawValue:)),
            isCustomized: isCustomized
        )
        mapping.displayName = displayName
        mapping.paramDescription = paramDescription
        mapping.valueType = valueType
        mapping.controlType = controlType
        mapping.minValue = minValue
        mapping.maxValue = maxValue
        mapping.step = step
        mapping.options = options
        return mapping
    }
}

struct ModelParameterAvailabilityExportData: Codable {
    let adapterIDRaw: String
    let semanticParameterID: String
    let isAvailable: Bool
    let isRequired: Bool
    let isIncludedByDefault: Bool
    let displayName: String
    let paramDescription: String
    let valueType: String
    let controlType: String
    let minValue: Double?
    let maxValue: Double?
    let step: Double?
    let options: [String]?
    let defaultValueData: Data?
    let isCustomized: Bool

    init(_ availability: ModelParameterAvailabilityItem) {
        adapterIDRaw = availability.adapterIDRaw
        semanticParameterID = availability.semanticParameterID
        isAvailable = availability.isAvailable
        isRequired = availability.isRequired
        isIncludedByDefault = availability.isIncludedByDefault
        displayName = availability.displayName
        paramDescription = availability.paramDescription
        valueType = availability.valueType
        controlType = availability.controlType
        minValue = availability.minValue
        maxValue = availability.maxValue
        step = availability.step
        options = availability.options
        defaultValueData = availability.defaultValueData
        isCustomized = availability.isCustomized
    }

    func toDataItem() -> ModelParameterAvailabilityItem {
        let availability = ModelParameterAvailabilityItem(
            adapterID: LLMAdapterID(rawValue: adapterIDRaw) ?? .openAIChatCompletions,
            semanticParameterID: LLMParameterID(rawValue: semanticParameterID) ?? .maxOutputTokens,
            isAvailable: isAvailable,
            isRequired: isRequired,
            isIncludedByDefault: isIncludedByDefault,
            isCustomized: isCustomized
        )
        availability.displayName = displayName
        availability.paramDescription = paramDescription
        availability.valueType = valueType
        availability.controlType = controlType
        availability.minValue = minValue
        availability.maxValue = maxValue
        availability.step = step
        availability.options = options
        availability.defaultValueData = defaultValueData
        return availability
    }
}
