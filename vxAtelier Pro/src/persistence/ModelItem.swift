import Foundation
import SwiftData

@Model
final class ModelItem {
    var modelID: String
    var apiConfiguration: APIConfigurationItem?
    var providerDisplayName: String?
    var providerContextSize: Int?
    var providerSupportedCapabilitiesRaw: [String]
    var providerUnsupportedCapabilitiesRaw: [String]
    var providerSupportedParametersRaw: [String]
    var providerUnsupportedParametersRaw: [String]
    var rawMetadataJSON: String?
    var displayNameOverride: String?
    var contextSizeOverride: Int?
    @Relationship(deleteRule: .cascade) var capabilityOverrides: [ModelCapabilityOverrideItem] = []
    @Relationship(deleteRule: .cascade) var parameterOverrides: [ModelParameterOverrideItem] = []

    var name: String { modelID }

    var providerMetadata: LLMProviderModelMetadata {
        let supported = providerSupportedCapabilitiesRaw.compactMap(LLMModelCapability.init(rawValue:)).map {
            LLMCapabilityClaim(capability: $0, state: .supported)
        }
        let unsupported = providerUnsupportedCapabilitiesRaw.compactMap(LLMModelCapability.init(rawValue:)).map {
            LLMCapabilityClaim(capability: $0, state: .unsupported)
        }
        let supportedParameters = providerSupportedParametersRaw.compactMap(LLMParameterID.init(rawValue:)).map {
            LLMParameterSupportClaim(parameterID: $0, state: .supported)
        }
        let unsupportedParameters = providerUnsupportedParametersRaw.compactMap(LLMParameterID.init(rawValue:)).map {
            LLMParameterSupportClaim(parameterID: $0, state: .unsupported)
        }
        return LLMProviderModelMetadata(
            id: modelID,
            displayName: providerDisplayName,
            providerID: providerID,
            contextSize: providerContextSize,
            capabilityClaims: supported + unsupported,
            parameterSupportClaims: supportedParameters + unsupportedParameters,
            rawMetadataJSON: rawMetadataJSON
        )
    }

    var providerID: LLMProviderID {
        apiConfiguration?.providerIDEnum ?? .customOpenAICompatible
    }

    var adapterID: LLMAdapterID {
        apiConfiguration?.defaultAdapterIDEnum ?? .openAICompatibleChatCompletions
    }

    var modelOverrides: LLMModelOverrides {
        let capabilityPairs: [(LLMModelCapability, LLMSupportState)] = capabilityOverrides.compactMap { item in
            guard item.support != .unknown else { return nil }
            return (item.capability, item.support)
        }
        let capabilitySupport = capabilityPairs.reduce(into: [LLMModelCapability: LLMSupportState]()) {
            $0[$1.0] = $1.1
        }
        let parameterSettings = parameterOverrides
            .filter { $0.adapterID == adapterID }
            .reduce(into: [LLMParameterID: LLMParameterOverrides]()) { $0[$1.parameterID] = $1.overrides }
        return LLMModelOverrides(
            displayName: displayNameOverride,
            contextSize: contextSizeOverride,
            capabilitySupport: capabilitySupport,
            parameterOverrides: parameterSettings
        )
    }

    var modelProfile: LLMModelProfile {
        LLMModelProfileResolver(fallbackContextSize: AppDefaults.ModelContextSizes.defaultSize).resolve(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID,
            metadata: providerMetadata,
            overrides: modelOverrides
        )
    }

    var displayName: String { modelProfile.displayName }
    var contextSize: Int { modelProfile.contextSize }
    var capabilities: [LLMModelCapability] { modelProfile.supportedCapabilities }

    init(
        modelID: String,
        contextSize: Int? = nil,
        apiConfiguration: APIConfigurationItem? = nil
    ) {
        self.modelID = modelID
        self.apiConfiguration = apiConfiguration
        providerDisplayName = nil
        providerContextSize = nil
        providerSupportedCapabilitiesRaw = []
        providerUnsupportedCapabilitiesRaw = []
        providerSupportedParametersRaw = []
        providerUnsupportedParametersRaw = []
        rawMetadataJSON = nil
        displayNameOverride = nil
        contextSizeOverride = contextSize
        capabilityOverrides = []
        parameterOverrides = []
    }

    convenience init(
        metadata: LLMProviderModelMetadata,
        apiConfiguration: APIConfigurationItem? = nil
    ) {
        self.init(modelID: metadata.id, apiConfiguration: apiConfiguration)
        apply(metadata)
    }

    func apply(_ metadata: LLMProviderModelMetadata) {
        modelID = metadata.id
        providerDisplayName = metadata.displayName
        providerContextSize = metadata.contextSize
        providerSupportedCapabilitiesRaw = metadata.capabilityClaims
            .filter { $0.state == .supported }
            .map { $0.capability.rawValue }
        providerUnsupportedCapabilitiesRaw = metadata.capabilityClaims
            .filter { $0.state == .unsupported }
            .map { $0.capability.rawValue }
        providerSupportedParametersRaw = metadata.parameterSupportClaims
            .filter { $0.state == .supported }
            .map { $0.parameterID.rawValue }
        providerUnsupportedParametersRaw = metadata.parameterSupportClaims
            .filter { $0.state == .unsupported }
            .map { $0.parameterID.rawValue }
        rawMetadataJSON = metadata.rawMetadataJSON
    }
}
