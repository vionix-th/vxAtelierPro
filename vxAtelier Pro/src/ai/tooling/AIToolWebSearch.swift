import Foundation
import SwiftData
import Observation // Add Observation for QueryManager

/// Tool for performing web searches using the configured default provider.
public struct WebSearchTool: ExecutableTool {
    public let name = "web_search"
    public let description = "Performs a web search. Takes a search query and the number of results desired (max 10)."

    // Add QueryManager property
    private let queryManager: QueryManager

    public var parameters: any AIToolParameters {
        GenericToolParameters(
            properties: [
                "query": GenericToolProperty(
                    type: "string",
                    description: "The search query term or phrase."
                ),
                "num_results": GenericToolProperty(
                    type: "integer",
                    description: "The desired number of search results."
                )
            ],
            required: ["query"] // Only query is strictly required
        )
    }

    // Make init internal (remove public)
    init(queryManager: QueryManager) {
        self.queryManager = queryManager
    }

    @MainActor // Ensure operations using QueryManager run on the main actor
    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        vxAtelierPro.log.info("🕸️ Executing web_search tool with arguments: \(arguments)")

        // 1. Parse Arguments
        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode([String: JSONValue].self, from: jsonData) else {
             let errorMsg = "Error: Invalid argument format. Expected JSON with 'query' (string) and optionally 'num_results' (integer)."
             vxAtelierPro.log.error("🔴 \(self.name): \(errorMsg)")
             return errorMsg
        }

        guard let queryValue = args["query"], case .string(let query) = queryValue, !query.isEmpty else {
             let errorMsg = "Error: Missing or invalid 'query' argument."
             vxAtelierPro.log.error("🔴 \(self.name): \(errorMsg)")
             return errorMsg
        }

        var numResults = 5
        if let numValue = args["num_results"], case .integer(let num) = numValue {
            numResults = max(1, min(10, num))
        } else if let numValue = args["num_results"], case .number(let num) = numValue {
            numResults = max(1, min(10, Int(num)))
        }
        vxAtelierPro.log.debug("🕸️ Search parameters: query='\(query)', num_results=\(numResults)")

        // 2. Get Default Search Configuration using QueryManager
        guard let searchConfig = queryManager.defaultWebSearchConfiguration else {
            let errorMsg = "Error: No default web search provider is configured in the application settings via QueryManager."
            vxAtelierPro.log.warning("⚠️ \(self.name): \(errorMsg)")
            return errorMsg
        }
        // Use 'provider' property
        vxAtelierPro.log.debug("🕸️ Found default search configuration: \(searchConfig.name) (\(searchConfig.provider))")

        // 3. Get Search Service using the Configuration
        let searchService: WebSearchService
        do {
            // Use 'with:' argument label
            searchService = try WebSearchServiceManager.shared.getService(with: searchConfig)
            // Use 'provider' property of the service's configuration
            vxAtelierPro.log.debug("🕸️ Obtained search service: \(searchService.configuration.providerName)")
        } catch _ as WebSearchError { // Replace 'let error' with '_'
             let errorMsg = "Error obtaining search service for configuration '\(searchConfig.name)': \(WebSearchError.invalidResponse.localizedDescription)" // Use a specific error if possible or generic message
             vxAtelierPro.log.error("🔴 \(self.name): \(errorMsg) - Error details: \(WebSearchError.invalidResponse.localizedDescription)") // Log the actual error type
             return errorMsg
        } catch {
             // Remove 'let errorMsg =' and inline the string
             vxAtelierPro.log.error("🔴 \(self.name): Error obtaining search service for configuration '\(searchConfig.name)': An unexpected error occurred. - Underlying error: \(error)")
            // Re-throw unexpected errors to allow higher-level handling if needed
            throw AppError.aiServiceError("Failed to get search service for config '\(searchConfig.name)': \(error.localizedDescription)")
        }

        // 4. Perform Search
        do {
            let results = try await searchService.search(query: query, numResults: numResults)
            vxAtelierPro.log.info("🕸️ Web search successful, received \(results.count) results.")

            if results.isEmpty {
                return "No results found for query: '\(query)'"
            }

            // 5. Format Results as JSON String
            let simplifiedResults = results.map { result -> [String: String?] in
                [
                    "title": result.title,
                    "link": result.link,
                    "snippet": result.snippet
                ]
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // Make output readable for debugging
            let jsonData = try encoder.encode(simplifiedResults)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                 throw AppError.encodingFailed("Failed to encode search results to JSON string.")
            }
            return jsonString

        } catch _ as WebSearchError { // Replace 'let error' with '_'
            let errorReason = "Unknown reason"
            let searchFailedError = WebSearchError.searchFailed(errorReason)
            let errorMsg = "Error during web search with service '\(searchConfig.provider)': \(searchFailedError.localizedDescription)" // Use specific error if possible
            vxAtelierPro.log.error("🔴 \(self.name): \(errorMsg) - Error details: \(searchFailedError)", file: #file, function: #function, line: #line) // Log actual error type
            return errorMsg
        } catch let error as AppError {
             let errorMsg = "Application error during web search: \(error.localizedDescription)"
             vxAtelierPro.log.error("🔴 \(self.name): \(errorMsg)", file: #file, function: #function, line: #line)
             return errorMsg // Return the error message instead of throwing
        } catch {
             vxAtelierPro.log.error("🔴 \(self.name): An unexpected error occurred during the web search with service '\(searchConfig.provider)'. - Underlying error: \(error)", file: #file, function: #function, line: #line)
            // Re-throw unexpected errors
            throw AppError.aiServiceError("Unexpected web search error: \(error.localizedDescription)")
        }
    }

    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}
