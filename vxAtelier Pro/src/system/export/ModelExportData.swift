import Foundation
import SwiftData

// MARK: - Model Export

struct ModelExportData: Codable {
    let name: String
    let contextSize: Int
    let provider: String
    let modelID: String?
    let displayName: String?
    let providerID: String?
    let adapterIDs: [String]?
    let modalities: [String]?
    let supportedParameters: [String]?
    let schemaFeatures: [String]?
    let rawMetadataJSON: String?
    let parameterMappings: [ModelParameterMappingExportData]?
    let apiConfigurationName: String?
    let apiConfigurationProviderID: String?
    let apiConfigurationBaseURL: String?
    
    init(_ model: ModelItem) {
        self.name = model.name
        self.contextSize = model.contextSize
        self.provider = model.provider
        self.modelID = model.modelID
        self.displayName = model.displayName
        self.providerID = model.providerID
        self.adapterIDs = model.adapterIDsRaw
        self.modalities = model.modalitiesRaw
        self.supportedParameters = model.supportedParameters
        self.schemaFeatures = model.schemaFeaturesRaw
        self.rawMetadataJSON = model.rawMetadataJSON
        self.parameterMappings = model.parameterMappings.map { ModelParameterMappingExportData($0) }
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
            name: name,
            contextSize: contextSize,
            provider: provider,
            apiConfiguration: apiConfiguration
        )
        model.modelID = modelID ?? name
        model.displayName = displayName ?? name
        model.providerID = providerID ?? LLMProviderRegistry.providerID(fromProviderName: provider).rawValue
        let defaultDescriptor = LLMModelDescriptorResolver().catalogDescriptor(
            for: model.modelID,
            providerID: LLMProviderID(rawValue: model.providerID) ?? .customOpenAICompatible
        )
        model.adapterIDsRaw = defaultDescriptor.adapterIDs.map(\.rawValue)
        model.modalitiesRaw = defaultDescriptor.modalities.map(\.rawValue)
        model.supportedParameters = defaultDescriptor.supportedParameters
        model.schemaFeaturesRaw = defaultDescriptor.schemaFeatures.map(\.rawValue)
        if let adapterIDs { model.adapterIDsRaw = adapterIDs }
        if let modalities { model.modalitiesRaw = modalities }
        if let supportedParameters { model.supportedParameters = supportedParameters }
        if let schemaFeatures { model.schemaFeaturesRaw = schemaFeatures }
        model.rawMetadataJSON = rawMetadataJSON
        model.parameterMappings = parameterMappings?.map { $0.toDataItem() } ?? []
        model.materializeDefaultParameterMappings(preserveCustomized: true)
        return model
    }
}

struct ModelParameterMappingExportData: Codable {
    let adapterIDRaw: String
    let semanticParameterID: String
    let isEnabled: Bool
    let isRequired: Bool
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
    let defaultValueData: Data?
    let isCustomized: Bool

    init(_ mapping: ModelParameterMappingItem) {
        adapterIDRaw = mapping.adapterIDRaw
        semanticParameterID = mapping.semanticParameterID
        isEnabled = mapping.isEnabled
        isRequired = mapping.isRequired
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
        defaultValueData = mapping.defaultValueData
        isCustomized = mapping.isCustomized
    }

    func toDataItem() -> ModelParameterMappingItem {
        let mapping = ModelParameterMappingItem(
            adapterID: LLMAdapterID(rawValue: adapterIDRaw) ?? .openAIChatCompletions,
            semanticParameterID: LLMParameterID(rawValue: semanticParameterID) ?? .maxOutputTokens,
            isEnabled: isEnabled,
            isRequired: isRequired,
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
        mapping.defaultValueData = defaultValueData
        return mapping
    }
}
