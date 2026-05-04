import Foundation

/// Utility for AI model provider detection and management.
///
/// This utility provides functionality to:
/// - Detect AI model providers from model names
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
    
} 
