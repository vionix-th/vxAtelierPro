import Foundation

/// Utility for AI model provider detection and management.
///
/// This utility provides functionality to:
/// - Detect AI model providers from model names
/// - Access standardized provider information
/// - Get default configurations for various providers
/// - Retrieve API-specific settings for each provider
/// - Infer model capabilities based on model name patterns
public enum ModelProviderUtils {
    
    /// Known AI model providers with standardized naming.
    ///
    /// This enum ensures consistent provider naming throughout the application
    /// and provides a centralized definition of supported AI services.
    public enum Provider: String {
        case openAI = "OpenAI"
        case anthropic = "Anthropic"
        case xAI = "xAI"
        case deepSeek = "DeepSeek"
        case google = "Google"
        case meta = "Meta"
        case mistral = "Mistral"
        case custom = "Custom"
        
        /// The display name for the provider.
        public var displayName: String {
            return self.rawValue
        }
    }
    
    /// Detects the AI provider based on model name patterns.
    ///
    /// Uses common naming conventions and prefixes to identify the most likely provider
    /// for a given model name. For example:
    /// - "gpt-4" → OpenAI
    /// - "claude-3" → Anthropic
    /// - "gemini-pro" → Google
    ///
    /// - Parameter modelName: The name of the model to analyze
    /// - Returns: The detected provider name as a string
    public static func detectProvider(from modelName: String) -> String {
        if modelName.starts(with: "gpt-") || 
           (modelName.hasPrefix("o") && modelName.contains("-")) || 
           modelName.contains("-davinci-") ||
           modelName.starts(with: "davinci") ||
           modelName.starts(with: "o1") ||
           modelName.contains("dall-e") ||
           modelName.starts(with: "chatgpt") ||
           modelName.starts(with: "text-embedding-") {
            return Provider.openAI.rawValue
        } else if modelName.starts(with: "claude-") {
            return Provider.anthropic.rawValue
        } else if modelName.starts(with: "grok-") {
            return Provider.xAI.rawValue
        } else if modelName.starts(with: "deepseek-") {
            return Provider.deepSeek.rawValue
        } else if modelName.starts(with: "gemini-") {
            return Provider.google.rawValue
        } else if modelName.starts(with: "llama-") || modelName.starts(with: "code-llama-") {
            return Provider.meta.rawValue
        } else if modelName.starts(with: "mixtral-") || modelName.starts(with: "mistral-") {
            return Provider.mistral.rawValue
        }
        return Provider.custom.rawValue
    }
    
    /// Returns the default base URL for a given provider.
    ///
    /// These URLs are standard API endpoints for each provider's services.
    /// Use this to configure API clients without hardcoding URLs.
    ///
    /// - Parameter provider: The provider to get the base URL for
    /// - Returns: The default base URL string, or empty string if not available
    public static func defaultBaseURL(for provider: Provider) -> String {
        switch provider {
        case .openAI:
            return AppDefaults.OpenAi.baseURL
        case .anthropic:
            return AppDefaults.Anthropic.baseURL
        case .xAI:
            return AppDefaults.XAI.baseURL
        case .deepSeek:
            return AppDefaults.DeepSeek.baseURL
        case .google:
            return "https://generativelanguage.googleapis.com"
        case .mistral:
            return "https://api.mistral.ai/v1"
        default:
            return ""
        }
    }
    
    /// Returns the default model for a given provider.
    ///
    /// These are reasonable default models that balance capability and cost
    /// for each provider. Use when the user hasn't specified a specific model.
    ///
    /// - Parameter provider: The provider to get the default model for
    /// - Returns: The default model name, or empty string if not available
    public static func defaultModel(for provider: Provider) -> String {
        switch provider {
        case .openAI:
            return AppDefaults.OpenAi.model
        case .anthropic:
            return AppDefaults.Anthropic.model
        case .xAI:
            return AppDefaults.XAI.model
        case .deepSeek:
            return AppDefaults.DeepSeek.model
        case .google:
            return "gemini-pro"
        case .mistral:
            return "mistral-medium"
        default:
            return ""
        }
    }
    
    /// Returns default header keys for API requests to a specific provider.
    ///
    /// This provides the expected authorization header format for each provider.
    /// The placeholder "API_KEY" should be replaced with the actual key.
    ///
    /// - Parameter provider: The provider to get header keys for
    /// - Returns: Dictionary of header keys and their standard name format
    public static func apiHeaderKeys(for provider: Provider) -> [String: String] {
        switch provider {
        case .openAI:
            return ["Authorization": "Bearer API_KEY"]
        case .anthropic:
            return ["x-api-key": "API_KEY", "anthropic-version": "2023-06-01"]
        case .google:
            return ["x-goog-api-key": "API_KEY"]
        case .mistral:
            return ["Authorization": "Bearer API_KEY"]
        default:
            return ["Authorization": "Bearer API_KEY"]
        }
    }
    
    /// Infers model capabilities based on the model name pattern.
    ///
    /// Uses common naming conventions and keywords to identify capabilities
    /// that a model is likely to support. This is useful when a ModelItem
    /// is not available in the database.
    ///
    /// - Parameter modelName: The name of the model to analyze
    /// - Returns: Array of ModelCapability enum values
    static func inferCapabilities(from modelName: String) -> [ModelCapability] {
        var capabilities: [ModelCapability] = []
        
        // Basic capabilities for all models
        capabilities.append(.text)
        capabilities.append(.chat)
        
        // Vision capability
        if modelName.contains("vision") || modelName.hasSuffix("-v") {
            capabilities.append(.vision)
        }
        
        // Function capability for GPT and Claude models
        if modelName.contains("gpt-4") || modelName.contains("gpt-3.5") 
            || modelName.contains("claude") 
            || modelName.contains("deepseek") 
            || modelName.contains("grok") 
        {
            capabilities.append(.function)
            // Most modern GPT and Claude models support streaming
            capabilities.append(.streaming)
        }
        
        // Image capability
        if modelName.contains("image") || modelName.contains("dall-e") || modelName.contains("grok") {
            capabilities.append(.image)
        }
        
        // Audio capability
        if modelName.contains("audio") || modelName.contains("speech") || modelName.contains("whisper") {
            capabilities.append(.audio)
        }
        
        // Video capability
        if modelName.contains("video") {
            capabilities.append(.video)
        }
        
        // Embedding capability
        if modelName.contains("embedding") {
            capabilities.append(.embedding)
        }
        
        return capabilities
    }
    
    /// Returns the capabilities a model is known to have based on its provider.
    ///
    /// This provides a more general capability inference based on the provider
    /// when the specific model name doesn't contain clear capability indicators.
    ///
    /// - Parameter provider: The model provider
    /// - Returns: Array of common capabilities for this provider's models
    static func commonCapabilities(for provider: String) -> [ModelCapability] {
        switch provider {
        case Provider.openAI.rawValue:
            return [.text, .chat, .function, .streaming]
        case Provider.anthropic.rawValue:
            return [.text, .chat, .function, .vision, .streaming]
        case Provider.google.rawValue:
            return [.text, .chat, .function, .vision, .streaming]
        default:
            return [.text, .chat]
        }
    }
} 

/// Represents different capabilities that AI models can support.
///
/// Each capability represents a distinct function the model can perform,
/// such as generating text, processing images, or handling audio data.
public enum ModelCapability: String, Codable, CaseIterable {
    /// Ability to generate text content (articles, stories, etc.)
    case text = "Text Generation"
    
    /// Ability to participate in conversational exchanges
    case chat = "Chat Completion"
    
    /// Ability to generate images from text descriptions
    case image = "Image Generation"
    
    /// Ability to process or generate audio content
    case audio = "Audio Processing"
    
    /// Ability to process or generate video content
    case video = "Video Processing"
    
    /// Ability to call functions or tools
    case function = "Function Calling"
    
    /// Ability to generate text embeddings for semantic search
    case embedding = "Text Embedding"
    
    /// Ability to analyze and understand images
    case vision = "Vision/Image Analysis"
    
    /// Ability to stream responses token by token
    case streaming = "Response Streaming"
    
    /// SF Symbol name representing this capability
    var systemName: String {
        switch self {
        case .text: return "text.justify"
        case .chat: return "bubble.left.and.bubble.right"
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "video"
        case .function: return "function"
        case .embedding: return "point.3.connected.trianglepath.dotted"
        case .vision: return "eye"
        case .streaming: return "sparkles"
        }
    }
}