import Foundation

/// Tool for retrieving the textual content or raw HTML of a website URL.
public struct ReadWebsiteTool: ExecutableTool {
    public let name = "read_website"
    public let description = "Fetches the content of a given web URL (http or https). Can return either a plain text summary (stripping HTML, scripts, styles, default behavior, truncated if long) or the full raw HTML content."

    // Limit the returned content size for summary to avoid overly large responses
    private let maxSummaryLength = 5000

    public var parameters: any AIToolParameters {
        GenericToolParameters(
            properties: [
                "url": GenericToolProperty(
                    type: "string",
                    description: "The full URL of the website to read (e.g., 'https://example.com')."
                ),
                "return_format": GenericToolProperty(
                    type: "string",
                    description: "Specify 'summary' for plain text content (default, truncated) or 'full_html' for the complete raw HTML.",
                    enumValues: ["summary", "full_html"]
                )
            ],
            required: ["url"] // return_format is optional, defaults to 'summary'
        )
    }

    public init() {}

    func execute(_ call: ToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
              let urlString = args["url"]
        else {
             return "Error: Invalid argument format. Expected a JSON object with 'url' and optionally 'return_format'."
        }

        // Determine the return format, defaulting to 'summary'
        let returnFormat = args["return_format"] ?? "summary"
        guard ["summary", "full_html"].contains(returnFormat) else {
             return "Error: Invalid 'return_format'. Must be 'summary' or 'full_html'."
        }

        guard let url = URL(string: urlString) else {
            return "Error: Invalid URL format provided: \(urlString)"
        }

        // Basic check for http/https scheme
        guard let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
             return "Error: URL must use http or https scheme."
        }

        do {
            // Perform network request
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                return "Error: Did not receive a valid HTTP response."
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return "Error: Website request failed with status code \(httpResponse.statusCode)."
            }

            // Decode data as UTF-8 string
            guard let rawContent = String(data: data, encoding: .utf8) else {
                return "Error: Failed to decode website content as UTF-8 text."
            }

            // Return based on requested format
            if returnFormat == "full_html" {
                 await vxAtelierPro.log.debug("ReadWebsiteTool: Returning full HTML for URL \(urlString)")
                 // Note: Returning full HTML without truncation. Be mindful of potential size.
                 return rawContent
            } else {
                // Check content type for summary - attempt to process text/html or text/plain
                if let contentType = httpResponse.mimeType,
                   !(contentType.lowercased().contains("text/html") || contentType.lowercased().contains("text/plain")) {
                     await vxAtelierPro.log.warning("ReadWebsiteTool (Summary): Received non-text content type '\(contentType)' from \(urlString). Attempting to parse anyway.")
                }

                // Summary format: Strip HTML and truncate
                let textContent = stripHTML(from: rawContent)

                if textContent.count > maxSummaryLength {
                    let truncatedText = String(textContent.prefix(maxSummaryLength)) + "... (summary truncated)"
                    await vxAtelierPro.log.debug("ReadWebsiteTool (Summary): Content truncated for URL \(urlString)")
                    return truncatedText
                } else if textContent.isEmpty {
                     return "Error: No readable text content found for summary at the URL."
                } else {
                    return textContent
                }
            }

        } catch let error as URLError {
            await vxAtelierPro.log.error("ReadWebsiteTool: Network error fetching URL \(urlString): \(error.localizedDescription)")
            return "Error: Network request failed: \(error.localizedDescription)"
        } catch {
            await vxAtelierPro.log.error("ReadWebsiteTool: Unexpected error fetching URL \(urlString): \(error.localizedDescription)")
            return "Error: An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    /// Basic HTML tag stripping function.
    private func stripHTML(from string: String) -> String {
        // Remove <script> and <style> blocks entirely first
        var processed = string.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?<\\/script>", with: "", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?<\\/style>", with: "", options: .regularExpression)
        // Remove remaining HTML tags
        processed = processed.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Replace common HTML entities
        processed = processed.replacingOccurrences(of: "&nbsp;", with: " ")
        processed = processed.replacingOccurrences(of: "&amp;", with: "&")
        processed = processed.replacingOccurrences(of: "&lt;", with: "<")
        processed = processed.replacingOccurrences(of: "&gt;", with: ">")
        processed = processed.replacingOccurrences(of: "&quot;", with: "\"")
        processed = processed.replacingOccurrences(of: "&apos;", with: "'")
        // Collapse multiple whitespaces/newlines into single spaces and trim
        processed = processed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return processed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 