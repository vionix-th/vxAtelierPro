import Foundation
import SwiftData

/// Shared resolver for persisted model metadata with bundled defaults as fallback.
struct LLMModelDescriptorResolver {
    var defaultsCatalog: LLMDefaultsCatalog = .bundled

    func defaultModelID(
        for providerID: LLMProviderID,
        apiConfiguration: APIConfigurationItem?
    ) -> String? {
        let configured = apiConfiguration?.defaultModelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let configured, !configured.isEmpty {
            return configured
        }
        return defaultsCatalog.defaultModelID(for: providerID)
    }

    func catalogDescriptor(
        for modelID: String,
        providerID: LLMProviderID,
        adapterIDs: [LLMAdapterID]? = nil
    ) -> LLMModelDescriptor {
        var descriptor = defaultsCatalog.modelDescriptor(
            providerID: providerID,
            modelID: modelID,
            adapterIDs: adapterIDs
        )
        if descriptor.adapterIDs.isEmpty, let adapterIDs {
            descriptor.adapterIDs = adapterIDs
        }
        return descriptor
    }

    @MainActor
    func descriptor(
        for modelID: String,
        providerID: LLMProviderID,
        apiConfiguration: APIConfigurationItem?,
        modelContext: ModelContext?,
        adapterIDs: [LLMAdapterID]? = nil
    ) throws -> LLMModelDescriptor {
        if let modelContext,
           let model = try persistedModel(
               modelID: modelID,
               providerID: providerID,
               apiConfiguration: apiConfiguration,
               modelContext: modelContext
           ) {
            model.materializeDefaultParameterMappings(preserveCustomized: true)
            return model.descriptor
        }

        return catalogDescriptor(
            for: modelID,
            providerID: providerID,
            adapterIDs: adapterIDs
        )
    }

    @MainActor
    private func persistedModel(
        modelID: String,
        providerID: LLMProviderID,
        apiConfiguration: APIConfigurationItem?,
        modelContext: ModelContext
    ) throws -> ModelItem? {
        let requestedModelID = modelID
        let requestedProviderID = providerID.rawValue
        let descriptor = FetchDescriptor<ModelItem>(
            predicate: #Predicate<ModelItem> { model in
                (model.modelID == requestedModelID || model.name == requestedModelID)
                    && model.providerID == requestedProviderID
            }
        )
        let models = try modelContext.fetch(descriptor)
        if let apiConfiguration {
            return models.first { $0.apiConfiguration?.id == apiConfiguration.id }
        }
        return models.first
    }
}
