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
    @Relationship(deleteRule: .cascade) var parameterMappingOverrides: [ModelParameterMappingOverrideItem] = []
    @Relationship(deleteRule: .cascade) var parameterPolicyOverrides: [ModelParameterPolicyOverrideItem] = []

    var name: String { modelID }

    var observation: LLMProviderModelObservation {
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
        return LLMProviderModelObservation(
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

    var contractOverrides: LLMModelContractOverrides {
        let capabilityPairs: [(LLMModelCapability, LLMSupportState)] = capabilityOverrides.compactMap { item in
            guard item.support != .unknown else { return nil }
            return (item.capability, item.support)
        }
        let capabilitySupport = capabilityPairs.reduce(into: [LLMModelCapability: LLMSupportState]()) {
            $0[$1.0] = $1.1
        }
        let mappings = parameterMappingOverrides
            .filter { $0.adapterID == adapterID }
            .reduce(into: [LLMParameterID: LLMParameterMapping]()) { $0[$1.parameterID] = $1.mapping }
        let policies = parameterPolicyOverrides
            .filter { $0.adapterID == adapterID }
            .reduce(into: [LLMParameterID: LLMParameterPolicyOverride]()) { $0[$1.parameterID] = $1.policy }
        return LLMModelContractOverrides(
            displayName: displayNameOverride,
            contextSize: contextSizeOverride,
            capabilitySupport: capabilitySupport,
            parameterMappings: mappings,
            parameterPolicies: policies
        )
    }

    var resolvedContract: LLMResolvedModelContract {
        LLMModelContractResolver(fallbackContextSize: AppDefaults.ModelContextSizes.defaultSize).resolve(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID,
            observation: observation,
            overrides: contractOverrides
        )
    }

    var displayName: String { resolvedContract.displayName }
    var contextSize: Int { resolvedContract.contextSize }
    var capabilities: [LLMModelCapability] { resolvedContract.supportedCapabilities }

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
        parameterMappingOverrides = []
        parameterPolicyOverrides = []
    }

    convenience init(
        observation: LLMProviderModelObservation,
        apiConfiguration: APIConfigurationItem? = nil
    ) {
        self.init(modelID: observation.id, apiConfiguration: apiConfiguration)
        apply(observation)
    }

    func apply(_ observation: LLMProviderModelObservation) {
        modelID = observation.id
        providerDisplayName = observation.displayName
        providerContextSize = observation.contextSize
        providerSupportedCapabilitiesRaw = observation.capabilityClaims
            .filter { $0.state == .supported }
            .map { $0.capability.rawValue }
        providerUnsupportedCapabilitiesRaw = observation.capabilityClaims
            .filter { $0.state == .unsupported }
            .map { $0.capability.rawValue }
        providerSupportedParametersRaw = observation.parameterSupportClaims
            .filter { $0.state == .supported }
            .map { $0.parameterID.rawValue }
        providerUnsupportedParametersRaw = observation.parameterSupportClaims
            .filter { $0.state == .unsupported }
            .map { $0.parameterID.rawValue }
        rawMetadataJSON = observation.rawMetadataJSON
    }
}
