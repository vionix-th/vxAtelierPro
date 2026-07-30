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
    let parameterOverrides: [ModelParameterOverrideExportData]
    let apiConfigurationName: String?
    let apiConfigurationProviderID: String?
    let apiConfigurationAdapterID: String?
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
        parameterOverrides = model.parameterOverrides.map(ModelParameterOverrideExportData.init)
        apiConfigurationName = model.apiConfiguration?.name
        apiConfigurationProviderID = model.apiConfiguration?.providerID
        apiConfigurationAdapterID = model.apiConfiguration?.adapterID
        apiConfigurationBaseURL = model.apiConfiguration?.baseURL
    }

    func toDataItem(apiConfigurations: [APIConfigurationItem] = []) throws -> ModelItem {
        try validateRouteIdentity()
        let apiConfiguration = apiConfigurations.first {
            $0.name == apiConfigurationName
                && $0.providerID == apiConfigurationProviderID
                && $0.adapterID == apiConfigurationAdapterID
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
        model.parameterOverrides = parameterOverrides.map(\.dataItem)
        return model
    }

    func validateRouteIdentity() throws {
        if let apiConfigurationProviderID,
           LLMProviderID(rawValue: apiConfigurationProviderID) == nil {
            throw LLMProviderError.invalidConfiguration(
                "Imported model references unknown provider id \(apiConfigurationProviderID)."
            )
        }
        if let apiConfigurationAdapterID,
           LLMAdapterID(rawValue: apiConfigurationAdapterID) == nil {
            throw LLMProviderError.invalidConfiguration(
                "Imported model references unknown generation adapter id \(apiConfigurationAdapterID)."
            )
        }
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

struct ModelParameterOverrideExportData: Codable {
    let adapterID: LLMAdapterID
    let parameterID: LLMParameterID
    let support: LLMSupportState?
    let encodingKind: LLMParameterEncodingKind?
    let wireKey: String?
    let structuredPreset: LLMParameterStructuredPreset?
    let requiredOverride: Bool?
    let enabledByDefaultOverride: Bool?
    let defaultValueOverrideKind: ModelDefaultValueOverrideKind
    let defaultValue: JSONValue?
    let optionsOverrideKind: ModelDefaultValueOverrideKind
    let options: [String]?

    init(_ item: ModelParameterOverrideItem) {
        adapterID = item.adapterID
        parameterID = item.parameterID
        support = item.support
        encodingKind = item.encodingKind
        wireKey = item.wireKey
        structuredPreset = item.structuredPreset
        requiredOverride = item.requiredOverride
        enabledByDefaultOverride = item.enabledByDefaultOverride
        defaultValueOverrideKind = item.defaultValueOverrideKind
        defaultValue = item.defaultValue
        optionsOverrideKind = item.optionsOverrideKind
        options = item.options
    }

    var dataItem: ModelParameterOverrideItem {
        ModelParameterOverrideItem(
            adapterID: adapterID,
            parameterID: parameterID,
            support: support,
            mapping: encodingKind.map {
                LLMParameterMapping(
                    adapterID: adapterID,
                    parameterID: parameterID,
                    encodingKind: $0,
                    wireKey: wireKey ?? "",
                    structuredPreset: structuredPreset
                )
            },
            requiredOverride: requiredOverride,
            enabledByDefaultOverride: enabledByDefaultOverride,
            defaultValueOverrideKind: defaultValueOverrideKind,
            defaultValue: defaultValue,
            optionsOverrideKind: optionsOverrideKind,
            options: options
        )
    }
}
