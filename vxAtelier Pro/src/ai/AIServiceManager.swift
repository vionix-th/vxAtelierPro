import Foundation
import SwiftData

// MARK: - Service Management

// Note: Extension removed as createCompletionRequest is now implemented directly in each service

/// Available AI service providers
enum AIServiceProvider: String, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case xAI = "xAI"
    case deepSeek = "DeepSeek"
    // Add other providers as needed
    
    /// Creates the appropriate AI service for the provider type
    func createService(with config: APIConfigurationItem) -> AIService {
        switch self {
        case .openAI:
            return OpenAIService(configurationItem: config)
            
        case .anthropic:
            return AnthropicService(configurationItem: config)
            
        case .xAI:
            return XAIService(configurationItem: config)
            
        case .deepSeek:
            return DeepSeekService(configurationItem: config)
        }
    }
    
    /// Determines the provider type from a base URL string
    static func detectProvider(from url: String) -> AIServiceProvider {
        let baseURL = url.lowercased()
        if baseURL.contains("anthropic") || baseURL.contains("claude") {
            return .anthropic
        }
        if baseURL.contains("x.ai") || baseURL.contains("grok") {
            return .xAI
        }
        if baseURL.contains("deepseek") {
            return .deepSeek
        }
        if baseURL.contains("openai") || baseURL.contains("api.openai.com") {
            return .openAI
        }
        // Default to OpenAI if no match found
        return .openAI
    }
    
    /// Determines the provider type from a configuration (uses baseURL, then modelsEndpoint)
    static func detectProvider(from config: APIConfigurationItem) -> AIServiceProvider {
        let providerFromBase = detectProvider(from: config.baseURL)
        if providerFromBase != .openAI || config.baseURL.lowercased().contains("openai") {
            return providerFromBase
        }
        // If not detected or defaulted to OpenAI, try modelsEndpoint as fallback
        return detectProvider(from: config.modelsEndpoint)
    }
}

/// Simplified manager for AI services
class AIServiceManager {
    // MARK: - Singleton Access
    
    static let shared = AIServiceManager()
        
    // MARK: - Service Management
    
    /// Get an AI service for a specific configuration object
    /// - Parameter config: The API configuration item
    /// - Returns: An initialized AI service
    func getService(with config: APIConfigurationItem) -> AIService {
        // Detect provider and create service
        let provider = AIServiceProvider.detectProvider(from: config)
        vxAtelierPro.log.debug("Creating service for provider: \(provider.rawValue)")
        
        return provider.createService(with: config)
    }
    
    /// Get the current default AI service
    /// - Parameter context: The model context to use for fetching configurations
    /// - Returns: An AI service instance using the default configuration
    func getCurrentService(context: ModelContext? = nil) -> AIService {
        // Use the provided context or create a new one
        if let context = context {
            return getDefaultService(using: context)
        } else {
            // Create a default service without requiring a context
            vxAtelierPro.log.warning("No context provided, using default OpenAI configuration")
            let defaultConfig = APIConfigurationItem()
            return AIServiceProvider.openAI.createService(with: defaultConfig)
        }
    }
    
    /// Get a default service using the provided context
    /// - Parameter context: The ModelContext to use for fetching configurations
    /// - Returns: An AI service with default configuration
    private func getDefaultService(using context: ModelContext) -> AIService {
        // Use the first available configuration as default if no specific one is selected
        let descriptor = FetchDescriptor<APIConfigurationItem>()
        
        do {
            if let config = try context.fetch(descriptor).first {
                vxAtelierPro.log.debug("Using first available configuration")
                let provider = AIServiceProvider.detectProvider(from: config)
                return provider.createService(with: config)
            } else {
                // Create a default OpenAI service with default configuration
                vxAtelierPro.log.warning("No configurations found, using OpenAI defaults")
                let defaultConfig = APIConfigurationItem()
                return AIServiceProvider.openAI.createService(with: defaultConfig)
            }
        } catch {
            vxAtelierPro.log.error("Error fetching configurations - \(error.localizedDescription)")
            // Return a default service as fallback
            let defaultConfig = APIConfigurationItem()
            return AIServiceProvider.openAI.createService(with: defaultConfig)
        }
    }
} 
