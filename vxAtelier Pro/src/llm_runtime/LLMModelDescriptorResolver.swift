import Foundation

/// Shared resolver for draft model candidates and provider defaults.
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
        providerID: LLMProviderID
    ) -> LLMModelDescriptor {
        defaultsCatalog.modelDescriptor(
            providerID: providerID,
            modelID: modelID
        )
    }
}
