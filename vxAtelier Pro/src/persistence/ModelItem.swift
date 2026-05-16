import AVFoundation
import Foundation
import Observation
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Represents an AI model for one API configuration.
///
/// This model stores information about AI models including:
/// - Base model name (e.g., "gpt-4", "claude-3")
/// - Context window size for token limits
/// - Model capabilities
@Model
final class ModelItem {
    /// Maximum context size in tokens that this model supports
    var contextSize: Int

    var modelID: String
    var displayName: String
    var apiConfiguration: APIConfigurationItem?
    var capabilitiesRaw: [String]
    var rawMetadataJSON: String?
    @Relationship(deleteRule: .cascade) var parameterMappings: [ModelParameterMappingItem] = []
    @Relationship(deleteRule: .cascade) var parameterAvailability: [ModelParameterAvailabilityItem] = []

    var name: String { modelID }

    var capabilities: [LLMModelCapability] {
        capabilitiesRaw.compactMap(LLMModelCapability.init(rawValue:))
    }

    var descriptor: LLMModelDescriptor {
        get {
            LLMModelDescriptor(
                id: modelID,
                displayName: displayName,
                providerID: apiConfiguration?.providerIDEnum ?? .customOpenAICompatible,
                contextSize: contextSize,
                capabilities: capabilities,
                rawMetadataJSON: rawMetadataJSON
            )
        }
        set {
            modelID = newValue.id
            displayName = newValue.displayName
            contextSize = newValue.contextSize ?? AppDefaults.ModelContextSizes.defaultSize
            capabilitiesRaw = newValue.capabilities.map(\.rawValue)
            rawMetadataJSON = newValue.rawMetadataJSON
            self.materializeDefaultParameterMappings(preserveCustomized: true)
            self.materializeDefaultParameterAvailability(preserveCustomized: true)
        }
    }

    /// Creates a new model item with the specified properties.
    ///
    /// - Parameters:
    ///   - modelID: The provider-facing model identifier
    ///   - contextSize: Maximum context size in tokens, defaults to app's default size
    init(
        modelID: String,
        contextSize: Int = AppDefaults.ModelContextSizes.defaultSize,
        apiConfiguration: APIConfigurationItem? = nil
    ) {
        self.modelID = modelID
        self.displayName = modelID
        self.contextSize = contextSize
        self.apiConfiguration = apiConfiguration
        self.capabilitiesRaw = []
        self.rawMetadataJSON = nil
        self.parameterMappings = []
        self.parameterAvailability = []

        let defaultCandidate = LLMModelDescriptorResolver().catalogDescriptor(
            for: modelID,
            providerID: apiConfiguration?.providerIDEnum ?? .customOpenAICompatible
        )
        self.contextSize = defaultCandidate.contextSize ?? contextSize
        self.capabilitiesRaw = defaultCandidate.capabilities.map(\.rawValue)
        self.materializeDefaultParameterMappings(preserveCustomized: true)
        self.materializeDefaultParameterAvailability(preserveCustomized: true)
    }

    func materializeDefaultParameterMappings(preserveCustomized: Bool = true) {
        guard let apiConfiguration else { return }
        materializeDefaultParameterMappings(
            adapterID: apiConfiguration.defaultAdapterIDEnum,
            providerID: apiConfiguration.providerIDEnum,
            preserveCustomized: preserveCustomized
        )
    }

    func resetDefaultParameterMappings(adapterID: LLMAdapterID) {
        guard let apiConfiguration else { return }
        materializeDefaultParameterMappings(
            adapterID: adapterID,
            providerID: apiConfiguration.providerIDEnum,
            preserveCustomized: false
        )
    }

    func materializeDefaultParameterAvailability(preserveCustomized: Bool = true) {
        guard let apiConfiguration else { return }
        materializeDefaultParameterAvailability(
            adapterID: apiConfiguration.defaultAdapterIDEnum,
            providerID: apiConfiguration.providerIDEnum,
            preserveCustomized: preserveCustomized
        )
    }

    func resetDefaultParameterAvailability(adapterID: LLMAdapterID) {
        guard let apiConfiguration else { return }
        materializeDefaultParameterAvailability(
            adapterID: adapterID,
            providerID: apiConfiguration.providerIDEnum,
            preserveCustomized: false
        )
    }

    convenience init(descriptor: LLMModelDescriptor, apiConfiguration: APIConfigurationItem? = nil) {
        self.init(
            modelID: descriptor.id,
            contextSize: descriptor.contextSize ?? AppDefaults.ModelContextSizes.defaultSize,
            apiConfiguration: apiConfiguration
        )
        self.descriptor = descriptor
    }

    private func materializeDefaultParameterMappings(
        adapterID: LLMAdapterID,
        providerID: LLMProviderID,
        preserveCustomized: Bool
    ) {
        let defaults = LLMParameterMappingCatalog.defaults(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID
        )

        for descriptor in defaults {
            if let existing = parameterMappings.first(where: {
                $0.adapterIDEnum == adapterID && $0.semanticParameterIDEnum == descriptor.semanticParameterID
            }) {
                if preserveCustomized && existing.isCustomized {
                    continue
                }
                existing.apply(descriptor, markCustomized: false)
            } else {
                parameterMappings.append(ModelParameterMappingItem(descriptor: descriptor))
            }
        }

        if !preserveCustomized {
            let defaultIDs = Set(defaults.map(\.semanticParameterID))
            parameterMappings.removeAll { mapping in
                mapping.adapterIDEnum == adapterID && !defaultIDs.contains(mapping.semanticParameterIDEnum)
            }
        }
    }

    private func materializeDefaultParameterAvailability(
        adapterID: LLMAdapterID,
        providerID: LLMProviderID,
        preserveCustomized: Bool
    ) {
        let defaults = LLMParameterAvailabilityCatalog.defaults(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID
        )

        for descriptor in defaults {
            if let existing = parameterAvailability.first(where: {
                $0.adapterIDEnum == adapterID && $0.semanticParameterIDEnum == descriptor.semanticParameterID
            }) {
                if preserveCustomized && existing.isCustomized {
                    continue
                }
                existing.apply(descriptor, markCustomized: false)
            } else {
                parameterAvailability.append(ModelParameterAvailabilityItem(descriptor: descriptor))
            }
        }

        if !preserveCustomized {
            let defaultIDs = Set(defaults.map(\.semanticParameterID))
            parameterAvailability.removeAll { availability in
                availability.adapterIDEnum == adapterID && !defaultIDs.contains(availability.semanticParameterIDEnum)
            }
        }
    }
}
