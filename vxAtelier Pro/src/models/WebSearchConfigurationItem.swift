import Foundation
import SwiftData

/// Represents a persisted configuration for a web search service provider.
@Model
public final class WebSearchConfigurationItem {
    /// Display name for this configuration (e.g., "My Google Search").
    public var name: String

    /// The type of provider this configuration is for (e.g., "Google", "Bing").
    /// Stored as a raw String value from `WebSearchProvider` enum.
    public var provider: String

    /// Authentication key for the API (e.g., Google API Key).
    /// Optional, as some providers might not require it or use different auth methods.
    public var apiKey: String?

    /// Search Engine Identifier (e.g., Google Custom Search Engine ID 'cx').
    /// Optional, specific to certain providers like Google.
    public var searchEngineId: String?

    /// Indicates if this configuration is the default one to use for searches.
    @Attribute public var isDefault: Bool

    /// Timestamp when the configuration was created.
    public var createdAt: Date

    public var providerEnum: WebSearchProvider {
        get { WebSearchProvider(rawValue: provider) ?? .custom }
        set { provider = newValue.rawValue }
    }

    /// Creates a new Web Search configuration.
    ///
    /// - Parameters:
    ///   - name: Display name for this configuration.
    ///   - provider: The provider type (use `WebSearchProvider.rawValue`).
    ///   - apiKey: Optional API key.
    ///   - searchEngineId: Optional Search Engine ID.
    ///   - isDefault: Whether this configuration should be the default.
    ///   - createdAt: The creation timestamp (defaults to now).
    public init(
        name: String = "New Web Search",
        provider: String = WebSearchProvider.google.rawValue, // Default to Google
        apiKey: String? = nil,
        searchEngineId: String? = nil,
        isDefault: Bool = false, // Default to false for new items
        createdAt: Date = .now
    ) {
        self.name = name
        self.provider = provider
        self.apiKey = apiKey
        self.searchEngineId = searchEngineId
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    public func makeWebSearchService() throws -> WebSearchService {
        try providerEnum.makeService(with: self)
    }
}
