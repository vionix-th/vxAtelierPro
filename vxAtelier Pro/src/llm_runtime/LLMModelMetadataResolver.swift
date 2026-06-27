import Foundation

/// Shared resolver for draft model candidates and provider defaults.
struct LLMModelMetadataResolver {
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

    func catalogMetadata(
        for modelID: String,
        providerID: LLMProviderID
    ) -> LLMModelMetadata {
        defaultsCatalog.modelMetadata(
            providerID: providerID,
            modelID: modelID
        )
    }
}
