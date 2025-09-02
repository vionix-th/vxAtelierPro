import Foundation
import SwiftData

/// Enum representing supported web search providers.
public enum WebSearchProvider: String, CaseIterable, Identifiable, Codable {
    case google = "Google"
    // case bing = "Bing" // Add more providers later
    // case duckduckgo = "DuckDuckGo"
    case custom = "Custom" // For manually configured ones if needed

    public var id: String { self.rawValue }

    public var displayName: String {
        return self.rawValue
    }

    /// Creates the appropriate WebSearchService based on the provider type and configuration.
    /// - Parameter config: The `WebSearchConfigurationItem` containing settings.
    /// - Returns: An initialized `WebSearchService` instance.
    /// - Throws: `WebSearchError` if the provider is unsupported or configuration is invalid.
    func createService(with config: WebSearchConfigurationItem) throws -> WebSearchService {
        switch self {
        case .google:
            // Ensure required fields for Google are present
            guard let apiKey = config.apiKey, !apiKey.isEmpty,
                  let cxId = config.searchEngineId, !cxId.isEmpty else {
                throw WebSearchError.missingCredentials("Google Custom Search (API Key and Search Engine ID are required)")
            }
            let googleConfig = GoogleCustomSearchConfiguration(
                providerName: self.rawValue,
                apiKey: apiKey,
                searchEngineId: cxId
            )
            return GoogleCustomSearchService(configuration: googleConfig)
        case .custom:
            // Handle custom provider creation if needed later
             throw WebSearchError.unsupportedProvider("Custom provider creation not implemented yet.")
        // Add cases for other providers (Bing, DDG, etc.) here
        }
    }

    /// Attempts to detect the provider based on configuration details (e.g., name).
    static func detectProvider(from config: WebSearchConfigurationItem) -> WebSearchProvider {
        let lowerName = config.name.lowercased()
        if lowerName.contains("google") {
            return .google
        }
        // Add detection logic for other providers if necessary
        return .custom // Default to custom if not detected
    }
}


/// Manages different web search service implementations.
public class WebSearchServiceManager {
    public static let shared = WebSearchServiceManager()

    private init() {
        vxAtelierPro.log.debug("🕸️ WebSearchServiceManager initialized")
    }

    /// Gets a web search service instance for a specific configuration item.
    /// - Parameter config: The `WebSearchConfigurationItem` to use.
    /// - Returns: An initialized `WebSearchService` instance.
    /// - Throws: `WebSearchError` if the service cannot be created.
    public func getService(with config: WebSearchConfigurationItem) throws -> WebSearchService {
        let provider = WebSearchProvider.detectProvider(from: config)
        vxAtelierPro.log.debug("🕸️ Creating web search service for provider: \(provider.rawValue) using config: \(config.name)")
        return try provider.createService(with: config)
    }

    /// Gets the default web search service based on the available configurations.
    /// - Parameter context: The `ModelContext` to fetch configurations from.
    /// - Returns: The default `WebSearchService` or `nil` if no default is configured or available.
    /// - Throws: `WebSearchError` if fetching or service creation fails.
    public func getDefaultService(context: ModelContext) throws -> WebSearchService? {
        let descriptor = FetchDescriptor<WebSearchConfigurationItem>(
            sortBy: [SortDescriptor(\.name)] // Consistent ordering
        )

        do {
            let configurations = try context.fetch(descriptor)

            // Find the one marked as default
            if let defaultConfig = configurations.first(where: { $0.isDefault }) {
                vxAtelierPro.log.debug("🕸️ Using default web search configuration: \(defaultConfig.name)")
                return try getService(with: defaultConfig)
            }

            // If no explicit default, use the first available one (optional)
            // else if let firstConfig = configurations.first {
            //     vxAtelierPro.log.warning("🕸️ No default web search config set, using first available: \(firstConfig.name)")
            //     return try getService(with: firstConfig)
            // }

            // No configurations available or no default found
            vxAtelierPro.log.notice("🕸️ No default web search configuration found.")
            return nil

        } catch {
            vxAtelierPro.log.error("🕸️ Failed to fetch web search configurations: \(error.localizedDescription)")
            throw WebSearchError.configurationError("Failed to fetch configurations: \(error.localizedDescription)")
        }
    }
} 