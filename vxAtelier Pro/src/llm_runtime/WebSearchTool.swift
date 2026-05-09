import Foundation
import SwiftData
import Observation

/// Executable tool that runs a web search through the configured default provider.
public struct WebSearchTool: ExecutableLLMTool {
    public let name = "web_search"
    public let description = "Performs a web search. Takes a search query and the number of results desired (max 10)."

    private let queryManager: QueryManager

    /// Requires a query and accepts an optional bounded result count.
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(
            properties: [
                "query": GenericLLMToolProperty(
                    type: "string",
                    description: "The search query term or phrase."
                ),
                "num_results": GenericLLMToolProperty(
                    type: "integer",
                    description: "The desired number of search results."
                )
            ],
            required: ["query"]
        )
    }

    /// Creates a web-search tool backed by the app query manager.
    init(queryManager: QueryManager) {
        self.queryManager = queryManager
    }

    /// Executes the search and returns simplified results as pretty-printed JSON.
    @MainActor
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        vxAtelierPro.log.info("Executing web_search tool with arguments: \(arguments)")

        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode([String: JSONValue].self, from: jsonData) else {
            let errorMsg = "Invalid argument format. Expected JSON with 'query' (string) and optionally 'num_results' (integer)."
            vxAtelierPro.log.error("\(self.name): \(errorMsg)")
            throw LLMToolExecutionError.invalidArguments(errorMsg)
        }

        guard let queryValue = args["query"], case .string(let query) = queryValue, !query.isEmpty else {
            let errorMsg = "Missing or invalid 'query' argument."
            vxAtelierPro.log.error("\(self.name): \(errorMsg)")
            throw LLMToolExecutionError.invalidArguments(errorMsg)
        }

        var numResults = 5
        if let numValue = args["num_results"], case .integer(let num) = numValue {
            numResults = max(1, min(10, num))
        } else if let numValue = args["num_results"], case .number(let num) = numValue {
            numResults = max(1, min(10, Int(num)))
        }
        vxAtelierPro.log.debug("Search parameters: query='\(query)', num_results=\(numResults)")

        guard let searchConfig = queryManager.defaultWebSearchConfiguration else {
            let errorMsg = "No default web search provider is configured in the application settings via QueryManager."
            vxAtelierPro.log.warning("\(self.name): \(errorMsg)")
            throw LLMToolExecutionError.unavailable(errorMsg)
        }
        vxAtelierPro.log.debug("Found default search configuration: \(searchConfig.name) (\(searchConfig.provider))")

        let searchService: WebSearchService
        do {
            searchService = try searchConfig.makeWebSearchService()
            vxAtelierPro.log.debug("Obtained search service: \(searchService.configuration.providerName)")
        } catch let error as WebSearchError {
            let errorMsg = "Error obtaining search service for configuration '\(searchConfig.name)': \(error.localizedDescription)"
            vxAtelierPro.log.error("\(self.name): \(errorMsg)")
            throw LLMToolExecutionError.unavailable(errorMsg)
        } catch {
            vxAtelierPro.log.error("\(self.name): Error obtaining search service for configuration '\(searchConfig.name)': An unexpected error occurred. - Underlying error: \(error)")
            throw AppError.aiServiceError("Failed to get search service for config '\(searchConfig.name)': \(error.localizedDescription)")
        }

        do {
            let results = try await searchService.search(query: query, numResults: numResults)
            vxAtelierPro.log.info("Web search successful, received \(results.count) results.")

            if results.isEmpty {
                return "No results found for query: '\(query)'"
            }

            let simplifiedResults = results.map { result -> [String: String?] in
                [
                    "title": result.title,
                    "link": result.link,
                    "snippet": result.snippet
                ]
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(simplifiedResults)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                 throw AppError.encodingFailed("Failed to encode search results to JSON string.")
            }
            return jsonString

        } catch let error as WebSearchError {
            let errorMsg = "Error during web search with service '\(searchConfig.provider)': \(error.localizedDescription)"
            vxAtelierPro.log.error("\(self.name): \(errorMsg)", file: #file, function: #function, line: #line)
            throw LLMToolExecutionError.executionFailed(errorMsg)
        } catch let error as AppError {
            let errorMsg = "Application error during web search: \(error.localizedDescription)"
            vxAtelierPro.log.error("\(self.name): \(errorMsg)", file: #file, function: #function, line: #line)
            throw LLMToolExecutionError.executionFailed(errorMsg)
        } catch {
            vxAtelierPro.log.error("\(self.name): An unexpected error occurred during the web search with service '\(searchConfig.provider)'. - Underlying error: \(error)", file: #file, function: #function, line: #line)
            throw AppError.aiServiceError("Unexpected web search error: \(error.localizedDescription)")
        }
    }
}
