import Foundation

// MARK: - Core Web Search Protocols & Types

/// Errors related to web search operations.
public enum WebSearchError: Error, LocalizedError {
    case invalidURL(String)
    case networkError(Error)
    case invalidResponse
    case apiError(message: String, statusCode: Int? = nil)
    case decodingError(Error)
    case missingCredentials(String) // e.g., "API Key required for Google Search"
    case configurationError(String)
    case unsupportedProvider(String)
    case searchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL configured for search service: \(url)"
        case .networkError(let error): return "Network error during search: \(error.localizedDescription)"
        case .invalidResponse: return "Received an invalid response from the search service."
        case .apiError(let message, let code):
            let codeString = code.map { " (Code: \($0))" } ?? ""
            return "Search API error: \(message)\(codeString)"
        case .decodingError(let error): return "Failed to decode search results: \(error.localizedDescription)"
        case .missingCredentials(let details): return "Missing required credentials: \(details)"
        case .configurationError(let details): return "Search configuration error: \(details)"
        case .unsupportedProvider(let name): return "The search provider '\(name)' is not supported."
        case .searchFailed(let reason): return "Web search failed: \(reason)"
        }
    }
}

/// Represents the configuration for a specific web search provider.
public protocol WebSearchConfiguration {
    var providerName: String { get }
    // Common fields can be added here if needed later
}

/// Represents a single search result item.
public struct WebSearchResult: Identifiable, Codable {
    public var id = UUID() // Local identifier for UI lists
    public let title: String
    public let link: String
    public let snippet: String
    public let displayLink: String? // Formatted URL for display
    public let source: String // e.g., "Google Custom Search"

    // Custom coding keys if the API field names differ significantly
    enum CodingKeys: String, CodingKey {
        case title, link, snippet, displayLink, source
        // id is not encoded/decoded from the API source
    }
}

/// Protocol defining the capabilities of a web search service.
public protocol WebSearchService {
    /// The configuration used by this service instance.
    var configuration: WebSearchConfiguration { get }

    /// Performs a web search query.
    /// - Parameter query: The search term or phrase.
    /// - Parameter numResults: The desired number of results (provider may limit).
    /// - Returns: An array of `WebSearchResult` items.
    /// - Throws: `WebSearchError` if the search fails.
    func search(query: String, numResults: Int) async throws -> [WebSearchResult]
}

/// A generic configuration structure, useful for providers that don't need specific fields.
public struct GenericWebSearchConfiguration: WebSearchConfiguration {
    public var providerName: String
} 