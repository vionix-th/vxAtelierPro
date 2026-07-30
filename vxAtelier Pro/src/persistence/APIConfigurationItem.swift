import Foundation
import SwiftData
import SwiftUI

/// Represents a configuration for an AI service API.
///
/// Stores connection details for AI service providers, including:
/// - Authentication credentials
/// - Service identifiers
/// - Base URLs
@Model
final class APIConfigurationItem {
    /// Display name for this configuration
    var name: String

    var providerID: String
    var authKind: String

    /// Authentication key for the API
    var apiKey: String

    /// Base URL for the API service
    var baseURL: String

    /// Indicates if this configuration is the default one
    @Attribute var isDefault: Bool

    /// The default model for this API configuration (overrides global defaults if set)
    var defaultModel: String?
    @Relationship(deleteRule: .cascade, inverse: \ModelItem.apiConfiguration) var models: [ModelItem] = []

    var adapterID: String
    var headersJSON: String
    var optionsJSON: String
    var credentialJSON: String

    var parsedProviderID: LLMProviderID? {
        LLMProviderID(rawValue: providerID)
    }

    var parsedAuthKind: LLMAuthKind? {
        LLMAuthKind(rawValue: authKind)
    }

    var parsedAdapterID: LLMAdapterID? {
        LLMAdapterID(rawValue: adapterID)
    }

    func requireProviderID() throws -> LLMProviderID {
        guard let parsedProviderID else {
            throw LLMProviderError.invalidConfiguration("Unknown provider id \(providerID).")
        }
        return parsedProviderID
    }

    func requireAdapterID() throws -> LLMAdapterID {
        guard let parsedAdapterID else {
            throw LLMProviderError.invalidConfiguration("Unknown generation adapter id \(adapterID).")
        }
        return parsedAdapterID
    }

    func requireAuthKind() throws -> LLMAuthKind {
        guard let parsedAuthKind else {
            throw LLMProviderError.invalidConfiguration("Unknown authentication kind \(authKind).")
        }
        return parsedAuthKind
    }

    var defaultModelID: String? {
        get { defaultModel }
        set { defaultModel = newValue }
    }

    var decodedHeaders: [String: String] {
        get { Self.decodeDictionary(headersJSON) }
        set { headersJSON = Self.encodeDictionary(newValue) }
    }

    var decodedOptions: [String: String] {
        get { Self.decodeDictionary(optionsJSON) }
        set { optionsJSON = Self.encodeDictionary(newValue) }
    }

    /// Creates a new API configuration with default or specified values.
    ///
    /// - Parameters:
    ///   - name: Display name for this configuration
    ///   - apiKey: Authentication key for the API
    ///   - baseURL: Base URL for the API service
    ///   - isDefault: Whether this configuration should be the default
    ///   - defaultModel: The default model for this configuration (optional)
    init(
        name: String = "Default",
        apiKey: String = AppDefaults.OpenAi.apiKey,
        baseURL: String = AppDefaults.OpenAi.baseURL,
        isDefault: Bool = false, // Default to false for new items
        defaultModel: String? = nil,
        providerID: LLMProviderID = .openAIPlatform
    ) {
        let profile = LLMProviderRegistry.shared.profile(for: providerID)
        let route = profile.defaultRoute
        self.name = name
        self.providerID = providerID.rawValue
        self.authKind = route?.defaultAuthKind.rawValue ?? LLMAuthKind.none.rawValue
        self.apiKey = route?.requiresCredential == true ? apiKey : ""
        self.baseURL = route?.requiresBaseURL == true ? baseURL : ""
        self.isDefault = isDefault
        self.defaultModel = defaultModel
        self.adapterID = profile.defaultAdapterID.rawValue
        self.headersJSON = "{}"
        self.optionsJSON = "{}"
        self.credentialJSON = "{}"
    }

    func makeLLMProviderConfiguration() throws -> LLMProviderConfiguration {
        let providerID = try requireProviderID()
        let adapterID = try requireAdapterID()
        let authKind = try requireAuthKind()
        var headers = try Self.validatedHeaders(decodedHeaders)
        var credential = apiKey
        if providerID == .openAICodexChatGPTSubscription,
           let tokenSet = codexChatGPTTokenSet {
            credential = tokenSet.accessToken
            if let accountID = tokenSet.accountID, !accountID.isEmpty {
                headers["ChatGPT-Account-Id"] = accountID
            }
            headers["originator"] = headers["originator"] ?? "vxatelier_pro"
        }
        let profile = LLMProviderRegistry.shared.profile(for: providerID)
        guard let route = profile.route(for: adapterID) else {
            throw LLMProviderError.invalidConfiguration(
                "\(profile.name) cannot use \(adapterID.displayName)."
            )
        }
        return Self.makeLLMProviderConfiguration(
            providerID: providerID,
            adapterID: adapterID,
            authKind: authKind,
            apiKey: authKind.requiresCredential ? credential : "",
            baseURL: route.requiresBaseURL ? baseURL : "",
            headers: headers,
            options: decodedOptions
        )
    }

    var codexChatGPTTokenSet: CodexChatGPTTokenSet? {
        get { CodexChatGPTTokenSet.decoded(from: credentialJSON)?.withClaimsFromTokens() }
        set { credentialJSON = newValue?.withClaimsFromTokens().encoded() ?? "{}" }
    }

    static func makeLLMProviderConfiguration(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        authKind: LLMAuthKind,
        apiKey: String,
        baseURL: String,
        headers: [String: String] = [:],
        options: [String: String] = [:]
    ) -> LLMProviderConfiguration {
        let profile = LLMProviderRegistry.shared.profile(for: providerID)
        let route = profile.route(for: adapterID)
        return LLMProviderConfiguration(
            providerID: providerID,
            authKind: authKind,
            baseURL: route?.requiresBaseURL == true
                ? (baseURL.isEmpty ? route?.defaultBaseURL ?? "" : baseURL)
                : "",
            credential: authKind.requiresCredential && !apiKey.isEmpty ? .secret(apiKey) : .none,
            customHeaders: sanitizedHeaders(headers, authKind: authKind),
            requestTimeout: Self.secondsOption("request_timeout_seconds", in: options, defaultValue: 60),
            streamIdleTimeout: Self.secondsOption("sse_idle_timeout_seconds", in: options, defaultValue: 120),
            maxResponseBodyBytes: Self.intOption("max_response_body_bytes", in: options, defaultValue: 10 * 1024 * 1024),
            maxSSEEventBytes: Self.intOption("max_sse_event_bytes", in: options, defaultValue: 1024 * 1024)
        )
    }

    private static func sanitizedHeaders(
        _ headers: [String: String],
        authKind: LLMAuthKind
    ) -> [String: String] {
        let ownedHeader: String?
        switch authKind {
        case .bearerToken, .codexChatGPTOAuth, .codexChatGPTDeviceCode:
            ownedHeader = "authorization"
        case .xAPIKey:
            ownedHeader = "x-api-key"
        case .none, .customHeaders:
            ownedHeader = nil
        }
        guard let ownedHeader else { return headers }
        return headers.filter { $0.key.lowercased() != ownedHeader }
    }

    private static func validatedHeaders(
        _ headers: [String: String]
    ) throws -> [String: String] {
        var normalizedNames = Set<String>()
        for name in headers.keys {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw LLMProviderError.invalidConfiguration("Custom header names cannot be empty.")
            }
            guard normalizedNames.insert(trimmedName.lowercased()).inserted else {
                throw LLMProviderError.invalidConfiguration(
                    "Custom header names must be unique, ignoring letter case."
                )
            }
        }
        return headers
    }

    private static func secondsOption(
        _ key: String,
        in options: [String: String],
        defaultValue: TimeInterval
    ) -> TimeInterval {
        guard let rawValue = options[key],
              let value = TimeInterval(rawValue),
              value > 0 else {
            return defaultValue
        }
        return value
    }

    private static func intOption(_ key: String, in options: [String: String], defaultValue: Int) -> Int {
        guard let rawValue = options[key],
              let value = Int(rawValue),
              value > 0 else {
            return defaultValue
        }
        return value
    }

    private static func decodeDictionary(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func encodeDictionary(_ dictionary: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(dictionary),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
