import Foundation

public enum WebSearchProvider: String, CaseIterable, Identifiable, Codable {
    case google = "Google"
    case custom = "Custom"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    func makeService(with config: WebSearchConfigurationItem) throws -> WebSearchService {
        switch self {
        case .google:
            guard let apiKey = config.apiKey, !apiKey.isEmpty,
                  let searchEngineID = config.searchEngineId, !searchEngineID.isEmpty else {
                throw WebSearchError.missingCredentials("Google Custom Search requires an API key and search engine ID.")
            }
            return GoogleCustomSearchService(
                configuration: GoogleCustomSearchConfiguration(
                    providerName: rawValue,
                    apiKey: apiKey,
                    searchEngineId: searchEngineID
                )
            )
        case .custom:
            throw WebSearchError.unsupportedProvider("Custom provider creation is not implemented.")
        }
    }
}
