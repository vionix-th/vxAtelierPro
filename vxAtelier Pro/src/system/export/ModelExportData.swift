import Foundation
import SwiftData

// MARK: - Model Export

struct ModelExportData: Codable {
    let name: String
    let contextSize: Int
    let provider: String
    let capabilities: [String]
    let modelID: String?
    let displayName: String?
    let providerID: String?
    let endpointFamilies: [String]?
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
        self.capabilities = model.capabilities.map { $0.rawValue }
        self.modelID = model.modelID
        self.displayName = model.displayName
        self.providerID = model.providerID
        self.endpointFamilies = model.endpointFamiliesRaw
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
        model.capabilities = capabilities.compactMap { ModelCapability(rawValue: $0) }
        model.modelID = modelID ?? name
        model.displayName = displayName ?? name
        model.providerID = providerID ?? LLMProviderRegistry.providerID(fromProviderName: provider).rawValue
        model.endpointFamiliesRaw = endpointFamilies ?? [LLMEndpointFamily.chatCompletions.rawValue]
        model.modalitiesRaw = modalities ?? [LLMModality.text.rawValue]
        model.supportedParameters = supportedParameters ?? []
        model.schemaFeaturesRaw = schemaFeatures ?? []
        model.rawMetadataJSON = rawMetadataJSON
        model.parameterMappings = parameterMappings?.map { $0.toDataItem() } ?? []
        LLMParameterMappingCatalog.materializeDefaults(on: model, preserveCustomized: true)
        return model
    }
}

struct ModelParameterMappingExportData: Codable {
    let endpointFamilyRaw: String
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
        endpointFamilyRaw = mapping.endpointFamilyRaw
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
            endpointFamily: LLMEndpointFamily(rawValue: endpointFamilyRaw) ?? .chatCompletions,
            semanticParameterID: LLMApplicationParameterID(rawValue: semanticParameterID) ?? .maxOutputTokens,
            isEnabled: isEnabled,
            isRequired: isRequired,
            encodingKind: ModelParameterEncodingKind(rawValue: encodingKindRaw) ?? .scalarKey,
            wireKey: wireKey,
            structuredPreset: structuredPresetRaw.flatMap(ModelParameterStructuredPreset.init(rawValue:)),
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
