import Foundation

/// Lifecycle state for a persisted LLM run.
enum LLMRunStatus: String, Codable, CaseIterable {
    case pending
    case streaming
    case awaitingTools
    case completed
    case failed
    case cancelled
}

/// Normalized error surface for provider configuration, transport, and decoding failures.
enum LLMProviderError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case invalidURL(String)
    case authUnavailable(String)
    case unsupportedCapability(String)
    case unsupportedParameter(String)
    case network(String)
    case provider(statusCode: Int, message: String, metadata: LLMResponseMetadata?)
    case decoding(String)
    case cancelled

    /// Presents the stored provider or validation failure as user-facing text.
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .invalidURL(let message): return message
        case .authUnavailable(let message): return message
        case .unsupportedCapability(let message): return message
        case .unsupportedParameter(let message): return message
        case .network(let message): return message
        case .provider(let statusCode, let message, _): return "Provider error \(statusCode): \(message)"
        case .decoding(let message): return message
        case .cancelled: return "Request cancelled."
        }
    }
}

/// Token accounting reported by a provider response.
struct LLMUsage: Codable, Equatable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?

    /// Creates token accounting from whichever counters the provider returned.
    init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

/// Redacted HTTP/provider metadata captured with an LLM response.
struct LLMResponseMetadata: Codable, Equatable {
    var statusCode: Int?
    var requestID: String?
    var retryAfter: String?
    var rateLimitHeaders: [String: String]
    var headers: [String: String]

    /// Creates redacted response metadata suitable for persistence and diagnostics.
    init(
        statusCode: Int? = nil,
        requestID: String? = nil,
        retryAfter: String? = nil,
        rateLimitHeaders: [String: String] = [:],
        headers: [String: String] = [:]
    ) {
        self.statusCode = statusCode
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.rateLimitHeaders = rateLimitHeaders
        self.headers = headers
    }
}
