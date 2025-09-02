import Foundation
import SwiftData
import SwiftUI

/// Represents a configuration for an AI service API.
///
/// Stores connection details for AI service providers, including:
/// - Authentication credentials
/// - API endpoints
/// - Service identifiers
/// - Base URLs
@Model
final class APIConfigurationItem {
    /// Display name for this configuration
    var name: String

    /// Authentication key for the API
    var apiKey: String

    /// Base URL for the API service
    var baseURL: String

    /// Endpoint for chat completion requests
    var chatCompletionsEndpoint: String

    /// Endpoint for listing available models
    var modelsEndpoint: String

    /// Indicates if this configuration is the default one
    @Attribute var isDefault: Bool

    /// The default model for this API configuration (overrides global defaults if set)
    var defaultModel: String?

    /// Creates a new API configuration with default or specified values.
    ///
    /// - Parameters:
    ///   - name: Display name for this configuration
    ///   - apiKey: Authentication key for the API
    ///   - baseURL: Base URL for the API service
    ///   - chatCompletionsEndpoint: Endpoint for chat requests
    ///   - modelsEndpoint: Endpoint for model listing
    ///   - isDefault: Whether this configuration should be the default
    ///   - defaultModel: The default model for this configuration (optional)
    init(
        name: String = "Default",
        apiKey: String = AppDefaults.OpenAi.apiKey,
        baseURL: String = AppDefaults.OpenAi.baseURL,
        chatCompletionsEndpoint: String = AppDefaults.OpenAi.chatCompletionsEndpoint,
        modelsEndpoint: String = AppDefaults.OpenAi.modelsEndpoint,
        isDefault: Bool = false, // Default to false for new items
        defaultModel: String? = nil
    ) {
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.chatCompletionsEndpoint = chatCompletionsEndpoint
        self.modelsEndpoint = modelsEndpoint
        self.isDefault = isDefault
        self.defaultModel = defaultModel
    }
} 