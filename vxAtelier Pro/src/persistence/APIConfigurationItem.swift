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

    var defaultAdapterID: String
    var headersJSON: String
    var optionsJSON: String
    var credentialJSON: String

    var providerIDEnum: LLMProviderID {
        get { LLMProviderID(rawValue: providerID) ?? .customOpenAICompatible }
        set { providerID = newValue.rawValue }
    }

    var authKindEnum: LLMAuthKind {
        get { LLMAuthKind(rawValue: authKind) ?? LLMProviderRegistry.shared.profile(for: providerIDEnum).authKind }
        set { authKind = newValue.rawValue }
    }

    var defaultAdapterIDEnum: LLMAdapterID {
        get { LLMAdapterID(rawValue: defaultAdapterID) ?? LLMProviderRegistry.shared.profile(for: providerIDEnum).defaultAdapterID }
        set { defaultAdapterID = newValue.rawValue }
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
        self.name = name
        self.providerID = providerID.rawValue
        self.authKind = profile.authKind.rawValue
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.isDefault = isDefault
        self.defaultModel = defaultModel
        self.defaultAdapterID = profile.defaultAdapterID.rawValue
        self.headersJSON = "{}"
        self.optionsJSON = "{}"
        self.credentialJSON = "{}"
    }

    func makeLLMProviderConfiguration() -> LLMProviderConfiguration {
        var headers = decodedHeaders
        var credential = apiKey
        if providerIDEnum == .openAICodexChatGPTSubscription,
           let tokenSet = codexChatGPTTokenSet {
            credential = tokenSet.accessToken
            if let accountID = tokenSet.accountID, !accountID.isEmpty {
                headers["ChatGPT-Account-Id"] = accountID
            }
            headers["originator"] = headers["originator"] ?? "vxatelier_pro"
        }
        return Self.makeLLMProviderConfiguration(
            providerID: providerIDEnum,
            authKind: authKindEnum,
            apiKey: credential,
            baseURL: baseURL,
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
        authKind: LLMAuthKind,
        apiKey: String,
        baseURL: String,
        headers: [String: String] = [:],
        options: [String: String] = [:]
    ) -> LLMProviderConfiguration {
        let profile = LLMProviderRegistry.shared.profile(for: providerID)
        return LLMProviderConfiguration(
            providerID: providerID,
            authKind: authKind,
            baseURL: baseURL.isEmpty ? profile.defaultBaseURL : baseURL,
            credential: apiKey.isEmpty ? .none : .secret(apiKey),
            customHeaders: headers,
            requestTimeout: Self.secondsOption("request_timeout_seconds", in: options, defaultValue: 60),
            streamIdleTimeout: Self.secondsOption("sse_idle_timeout_seconds", in: options, defaultValue: 120),
            maxResponseBodyBytes: Self.intOption("max_response_body_bytes", in: options, defaultValue: 10 * 1024 * 1024),
            maxSSEEventBytes: Self.intOption("max_sse_event_bytes", in: options, defaultValue: 1024 * 1024)
        )
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
