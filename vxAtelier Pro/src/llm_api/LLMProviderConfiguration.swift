import Foundation

/// Provider credential material after runtime configuration is resolved.
enum LLMProviderCredential: Codable, Equatable {
    case none
    case secret(String)
}

/// Runtime provider transport settings used by adapters and HTTP clients.
struct LLMProviderConfiguration: Codable, Equatable {
    var providerID: LLMProviderID
    var authKind: LLMAuthKind?
    var baseURL: String
    var credential: LLMProviderCredential
    var customHeaders: [String: String]
    var requestTimeout: TimeInterval
    var streamIdleTimeout: TimeInterval
    var maxResponseBodyBytes: Int
    var maxSSEEventBytes: Int

    /// Creates runtime transport settings after persisted configuration has been resolved.
    init(
        providerID: LLMProviderID,
        authKind: LLMAuthKind? = nil,
        baseURL: String,
        credential: LLMProviderCredential = .none,
        customHeaders: [String: String] = [:],
        requestTimeout: TimeInterval = 60,
        streamIdleTimeout: TimeInterval = 120,
        maxResponseBodyBytes: Int = 10 * 1024 * 1024,
        maxSSEEventBytes: Int = 1024 * 1024
    ) {
        self.providerID = providerID
        self.authKind = authKind
        self.baseURL = baseURL
        self.credential = credential
        self.customHeaders = customHeaders
        self.requestTimeout = requestTimeout
        self.streamIdleTimeout = streamIdleTimeout
        self.maxResponseBodyBytes = maxResponseBodyBytes
        self.maxSSEEventBytes = maxSSEEventBytes
    }
}

/// Builds protocol headers from provider auth kind and runtime credentials.
enum LLMProviderHeaderResolver {
    /// Merges custom headers with the auth header required by the resolved provider.
    static func headers(for configuration: LLMProviderConfiguration) -> [String: String] {
        let profile = LLMProviderRegistry.shared.profile(for: configuration.providerID)
        let authKind = configuration.authKind ?? profile.authKind
        var headers = configuration.customHeaders

        switch (authKind, configuration.credential) {
        case (.bearerToken, .secret(let secret)):
            headers["Authorization"] = "Bearer \(secret)"
        case (.xAPIKey, .secret(let secret)):
            headers["x-api-key"] = secret
            headers["anthropic-version"] = headers["anthropic-version"] ?? "2023-06-01"
        case (.none, _), (.customHeaders, _), (_, .none):
            break
        case (.chatGPTOAuth, _), (.chatGPTDeviceCode, _), (.chatGPTCodexToken, _):
            break
        }

        return headers
    }
}
