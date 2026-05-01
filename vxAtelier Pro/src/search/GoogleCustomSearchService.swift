import Foundation

// MARK: - Google Custom Search Codable Types

/// Codable structures matching the Google Custom Search JSON API response.
/// See: https://developers.google.com/custom-search/v1/reference/rest/v1/cse/list
private enum GoogleApiCodableTypes {
    struct SearchResponse: Codable {
        let items: [SearchItem]?
        let error: ApiError? // Capture API-level errors
    }

    struct SearchItem: Codable {
        let title: String?
        let link: String?
        let snippet: String?
        let displayLink: String?
        // Add other fields if needed, e.g., pagemap for images
    }

    struct ApiError: Codable {
        let code: Int?
        let message: String?
        // We might not need the 'errors' array for basic handling
    }
}

// MARK: - Google Custom Search Configuration

/// Configuration specific to the Google Custom Search API.
public struct GoogleCustomSearchConfiguration: WebSearchConfiguration {
    public var providerName: String // Should be "Google"
    public let apiKey: String
    public let searchEngineId: String // Also known as 'cx'

    // Base URL for the Google Custom Search API
    static let apiBaseUrl = "https://www.googleapis.com/customsearch/v1"
}

// MARK: - Google Custom Search Service Implementation

/// Implements the `WebSearchService` protocol for Google Custom Search.
public class GoogleCustomSearchService: WebSearchService {
    public let configuration: WebSearchConfiguration

    private let networkClient = NetworkClient.shared

    /// Initializes the service with Google-specific configuration.
    init(configuration: GoogleCustomSearchConfiguration) {
        self.configuration = configuration
        vxAtelierPro.log.debug("🕸️ GoogleCustomSearchService initialized with cx: \(configuration.searchEngineId)")
    }

    /// Performs a search using the Google Custom Search API.
    public func search(query: String, numResults: Int) async throws -> [WebSearchResult] {
        guard let googleConfig = configuration as? GoogleCustomSearchConfiguration else {
            throw WebSearchError.configurationError("Invalid configuration type for GoogleCustomSearchService.")
        }

        // Construct the API URL
        guard var components = URLComponents(string: GoogleCustomSearchConfiguration.apiBaseUrl) else {
            throw WebSearchError.invalidURL(GoogleCustomSearchConfiguration.apiBaseUrl)
        }

        components.queryItems = [
            URLQueryItem(name: "key", value: googleConfig.apiKey),
            URLQueryItem(name: "cx", value: googleConfig.searchEngineId),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "num", value: String(max(1, min(10, numResults)))) // Google allows 1-10 results per page
            // Add other parameters if needed (e.g., siteSearch, lr for language)
        ]

        guard let url = components.url else {
            throw WebSearchError.invalidURL("Failed to construct Google Search API URL")
        }

        await vxAtelierPro.log.debug("🕸️ Performing Google Search: \(url.absoluteString)")

        do {
            // Perform GET request - Google Custom Search uses GET
            let response: GoogleApiCodableTypes.SearchResponse = try await networkClient.getRequest(
                url: url.absoluteString,
                headers: [:], // No special headers needed beyond API key in URL
                responseType: GoogleApiCodableTypes.SearchResponse.self
            )

            // Check for API-level errors returned in the JSON body
            if let apiError = response.error {
                await vxAtelierPro.log.error("🔴 Google Search API Error (Code: \(apiError.code ?? -1)): \(apiError.message ?? "Unknown error")")
                throw WebSearchError.apiError(message: apiError.message ?? "Unknown API Error", statusCode: apiError.code)
            }

            // Map API response items to our generic WebSearchResult
            let results = response.items?.compactMap { item -> WebSearchResult? in
                guard let title = item.title, let link = item.link, let snippet = item.snippet else {
                    return nil // Skip items missing essential fields
                }
                return WebSearchResult(
                    title: title,
                    link: link,
                    snippet: snippet,
                    displayLink: item.displayLink,
                    source: googleConfig.providerName // Use the provider name from config
                )
            } ?? [] // Return empty array if items array is nil

            await vxAtelierPro.log.info("🕸️ Google Search successful, received \(results.count) results for query: '\(query)'")
            return results

        } catch let networkError as NetworkError {
            await vxAtelierPro.log.error("🔴 Google Search Network Error: \(networkError.localizedDescription)")
            // Re-throw as a WebSearchError for consistency
            switch networkError {
                case .serverError(let statusCode, let message, _):
                     throw WebSearchError.apiError(message: message, statusCode: statusCode)
                 default:
                     throw WebSearchError.networkError(networkError)
            }
        } catch let decodingError as DecodingError {
            await vxAtelierPro.log.error("🔴 Google Search Decoding Error: \(decodingError.localizedDescription)")
            throw WebSearchError.decodingError(decodingError)
        } catch {
            // Catch any other unexpected errors
            await vxAtelierPro.log.error("🔴 Google Search Unexpected Error: \(error.localizedDescription)")
            throw WebSearchError.searchFailed(error.localizedDescription)
        }
    }
}
