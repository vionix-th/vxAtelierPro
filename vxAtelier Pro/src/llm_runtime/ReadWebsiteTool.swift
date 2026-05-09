import Foundation

/// Executable tool that fetches text summary or raw HTML from an HTTP(S) URL.
public struct ReadWebsiteTool: ExecutableLLMTool {
    public let name = "read_website"
    public let description = "Fetches the content of a given web URL (http or https). Can return either a plain text summary (stripping HTML, scripts, styles, default behavior, truncated if long) or the full raw HTML content."

    /// Maximum plain-text summary length returned to the model.
    private let maxSummaryLength = 5000

    /// Requires a URL and accepts `summary` or `full_html` return format.
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(
            properties: [
                "url": GenericLLMToolProperty(
                    type: "string",
                    description: "The full URL of the website to read (e.g., 'https://example.com')."
                ),
                "return_format": GenericLLMToolProperty(
                    type: "string",
                    description: "Specify 'summary' for plain text content (default, truncated) or 'full_html' for the complete raw HTML.",
                    enumValues: ["summary", "full_html"]
                )
            ],
            required: ["url"]
        )
    }

    /// Creates a website reader tool.
    public init() {}

    /// Fetches the URL and returns either raw HTML or stripped, truncated text.
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
              let urlString = args["url"]
        else {
            throw LLMToolExecutionError.invalidArguments("Invalid argument format. Expected a JSON object with 'url' and optionally 'return_format'.")
        }

        let returnFormat = args["return_format"] ?? "summary"
        guard ["summary", "full_html"].contains(returnFormat) else {
            throw LLMToolExecutionError.invalidArguments("Invalid 'return_format'. Must be 'summary' or 'full_html'.")
        }

        guard let url = URL(string: urlString) else {
            throw LLMToolExecutionError.invalidArguments("Invalid URL format provided: \(urlString)")
        }

        guard let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            throw LLMToolExecutionError.invalidArguments("URL must use http or https scheme.")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMToolExecutionError.executionFailed("Did not receive a valid HTTP response.")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw LLMToolExecutionError.executionFailed("Website request failed with status code \(httpResponse.statusCode).")
            }

            guard let rawContent = String(data: data, encoding: .utf8) else {
                throw LLMToolExecutionError.executionFailed("Failed to decode website content as UTF-8 text.")
            }

            if returnFormat == "full_html" {
                 vxAtelierPro.log.debug("ReadWebsiteTool: Returning full HTML for URL \(urlString)")
                 return rawContent
            } else {
                if let contentType = httpResponse.mimeType,
                   !(contentType.lowercased().contains("text/html") || contentType.lowercased().contains("text/plain")) {
                     vxAtelierPro.log.warning("ReadWebsiteTool (Summary): Received non-text content type '\(contentType)' from \(urlString). Attempting to parse anyway.")
                }

                let textContent = stripHTML(from: rawContent)

                if textContent.count > maxSummaryLength {
                    let truncatedText = String(textContent.prefix(maxSummaryLength)) + "... (summary truncated)"
                    vxAtelierPro.log.debug("ReadWebsiteTool (Summary): Content truncated for URL \(urlString)")
                    return truncatedText
                } else if textContent.isEmpty {
                    throw LLMToolExecutionError.executionFailed("No readable text content found for summary at the URL.")
                } else {
                    return textContent
                }
            }

        } catch let error as URLError {
            vxAtelierPro.log.error("ReadWebsiteTool: Network error fetching URL \(urlString): \(error.localizedDescription)")
            throw LLMToolExecutionError.executionFailed("Network request failed: \(error.localizedDescription)")
        } catch let error as LLMToolExecutionError {
            throw error
        } catch {
            vxAtelierPro.log.error("ReadWebsiteTool: Unexpected error fetching URL \(urlString): \(error.localizedDescription)")
            throw LLMToolExecutionError.executionFailed("An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    /// Removes scripts, styles, tags, common entities, and excess whitespace from HTML.
    private func stripHTML(from string: String) -> String {
        var processed = string.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?<\\/script>", with: "", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?<\\/style>", with: "", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "&nbsp;", with: " ")
        processed = processed.replacingOccurrences(of: "&amp;", with: "&")
        processed = processed.replacingOccurrences(of: "&lt;", with: "<")
        processed = processed.replacingOccurrences(of: "&gt;", with: ">")
        processed = processed.replacingOccurrences(of: "&quot;", with: "\"")
        processed = processed.replacingOccurrences(of: "&apos;", with: "'")
        processed = processed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return processed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
