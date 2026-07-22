import Foundation

struct ModelExportData: Codable {
    let modelID: String
    let providerDisplayName: String?
    let providerContextSize: Int?
    let providerSupportedCapabilities: [String]
    let providerUnsupportedCapabilities: [String]
    let providerSupportedParameters: [String]
    let providerUnsupportedParameters: [String]
    let rawMetadataJSON: String?
    let displayNameOverride: String?
    let contextSizeOverride: Int?
    let capabilityOverrides: [ModelCapabilityOverrideExportData]
    let mappingOverrides: [ModelParameterMappingOverrideExportData]
    let policyOverrides: [ModelParameterPolicyOverrideExportData]
    let apiConfigurationName: String?
    let apiConfigurationProviderID: String?
    let apiConfigurationBaseURL: String?

    init(_ model: ModelItem) {
        modelID = model.modelID
        providerDisplayName = model.providerDisplayName
        providerContextSize = model.providerContextSize
        providerSupportedCapabilities = model.providerSupportedCapabilitiesRaw
        providerUnsupportedCapabilities = model.providerUnsupportedCapabilitiesRaw
        providerSupportedParameters = model.providerSupportedParametersRaw
        providerUnsupportedParameters = model.providerUnsupportedParametersRaw
        rawMetadataJSON = model.rawMetadataJSON
        displayNameOverride = model.displayNameOverride
        contextSizeOverride = model.contextSizeOverride
        capabilityOverrides = model.capabilityOverrides.map(ModelCapabilityOverrideExportData.init)
        mappingOverrides = model.parameterMappingOverrides.map(ModelParameterMappingOverrideExportData.init)
        policyOverrides = model.parameterPolicyOverrides.map(ModelParameterPolicyOverrideExportData.init)
        apiConfigurationName = model.apiConfiguration?.name
        apiConfigurationProviderID = model.apiConfiguration?.providerID
        apiConfigurationBaseURL = model.apiConfiguration?.baseURL
    }

    func toDataItem(apiConfigurations: [APIConfigurationItem] = []) -> ModelItem {
        let apiConfiguration = apiConfigurations.first {
            $0.name == apiConfigurationName
                && $0.providerID == apiConfigurationProviderID
                && $0.baseURL == apiConfigurationBaseURL
        }
        let model = ModelItem(modelID: modelID, apiConfiguration: apiConfiguration)
        model.providerDisplayName = providerDisplayName
        model.providerContextSize = providerContextSize
        model.providerSupportedCapabilitiesRaw = providerSupportedCapabilities
        model.providerUnsupportedCapabilitiesRaw = providerUnsupportedCapabilities
        model.providerSupportedParametersRaw = providerSupportedParameters
        model.providerUnsupportedParametersRaw = providerUnsupportedParameters
        model.rawMetadataJSON = rawMetadataJSON
        model.displayNameOverride = displayNameOverride
        model.contextSizeOverride = contextSizeOverride
        model.capabilityOverrides = capabilityOverrides.map(\.dataItem)
        model.parameterMappingOverrides = mappingOverrides.map(\.dataItem)
        model.parameterPolicyOverrides = policyOverrides.map(\.dataItem)
        return model
    }
}

struct ModelCapabilityOverrideExportData: Codable {
    let capability: LLMModelCapability
    let support: LLMSupportState

    init(_ item: ModelCapabilityOverrideItem) {
        capability = item.capability
        support = item.support
    }

    var dataItem: ModelCapabilityOverrideItem {
        ModelCapabilityOverrideItem(capability: capability, support: support)
    }
}

struct ModelParameterMappingOverrideExportData: Codable {
    let adapterID: LLMAdapterID
    let parameterID: LLMParameterID
    let encodingKind: LLMParameterEncodingKind
    let wireKey: String
    let structuredPreset: LLMParameterStructuredPreset?

    init(_ item: ModelParameterMappingOverrideItem) {
        adapterID = item.adapterID
        parameterID = item.parameterID
        encodingKind = item.encodingKind
        wireKey = item.wireKey
        structuredPreset = item.structuredPreset
    }

    var dataItem: ModelParameterMappingOverrideItem {
        ModelParameterMappingOverrideItem(mapping: LLMParameterMapping(
            adapterID: adapterID,
            parameterID: parameterID,
            encodingKind: encodingKind,
            wireKey: wireKey,
            structuredPreset: structuredPreset
        ))
    }
}

struct ModelParameterPolicyOverrideExportData: Codable {
    let adapterID: LLMAdapterID
    let parameterID: LLMParameterID
    let support: LLMSupportState?
    let requiredOverride: Bool?
    let enabledByDefaultOverride: Bool?
    let defaultValueOverrideKind: ModelDefaultValueOverrideKind
    let defaultValue: JSONValue?

    init(_ item: ModelParameterPolicyOverrideItem) {
        adapterID = item.adapterID
        parameterID = item.parameterID
        support = item.support
        requiredOverride = item.requiredOverride
        enabledByDefaultOverride = item.enabledByDefaultOverride
        defaultValueOverrideKind = item.defaultValueOverrideKind
        defaultValue = item.defaultValue
    }

    var dataItem: ModelParameterPolicyOverrideItem {
        ModelParameterPolicyOverrideItem(
            adapterID: adapterID,
            parameterID: parameterID,
            support: support,
            requiredOverride: requiredOverride,
            enabledByDefaultOverride: enabledByDefaultOverride,
            defaultValueOverrideKind: defaultValueOverrideKind,
            defaultValue: defaultValue
        )
    }
}
