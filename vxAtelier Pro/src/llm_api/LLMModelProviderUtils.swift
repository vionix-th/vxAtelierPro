import Foundation

/// Heuristics for provider and capability detection when persisted model metadata is unavailable.
public enum LLMModelProviderUtils {
    
    /// Provider names inferred from common model naming conventions.
    public enum Provider: String {
        case openAI = "OpenAI"
        case anthropic = "Anthropic"
        case xAI = "xAI"
        case deepSeek = "DeepSeek"
        case google = "Google"
        case meta = "Meta"
        case mistral = "Mistral"
        case custom = "Custom"
        
        /// Human-facing provider name.
        public var displayName: String {
            return self.rawValue
        }
    }
    
    /// Infers the most likely provider from a model identifier or display name.
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

    /// Infers likely model capabilities from common model-name tokens.
    static func inferCapabilities(from modelName: String) -> [ModelCapability] {
        var capabilities: [ModelCapability] = []
        
        capabilities.append(.text)
        capabilities.append(.chat)
        
        if modelName.contains("vision") || modelName.hasSuffix("-v") {
            capabilities.append(.vision)
        }
        
        if modelName.contains("gpt-4") || modelName.contains("gpt-3.5") 
            || modelName.contains("claude") 
            || modelName.contains("deepseek") 
            || modelName.contains("grok") 
        {
            capabilities.append(.function)
            capabilities.append(.streaming)
        }
        
        if modelName.contains("image") || modelName.contains("dall-e") || modelName.contains("grok") {
            capabilities.append(.image)
        }
        
        if modelName.contains("audio") || modelName.contains("speech") || modelName.contains("whisper") {
            capabilities.append(.audio)
        }
        
        if modelName.contains("video") {
            capabilities.append(.video)
        }
        
        if modelName.contains("embedding") {
            capabilities.append(.embedding)
        }
        
        return capabilities
    }
} 

/// Legacy display capabilities inferred for imported or ad hoc models.
public enum ModelCapability: String, Codable, CaseIterable {
    /// Text generation support.
    case text = "Text Generation"
    
    /// Chat-style message exchange support.
    case chat = "Chat Completion"
    
    /// Image generation support.
    case image = "Image Generation"
    
    /// Audio processing support.
    case audio = "Audio Processing"
    
    /// Video processing support.
    case video = "Video Processing"
    
    /// Function or tool calling support.
    case function = "Function Calling"
    
    /// Text embedding support.
    case embedding = "Text Embedding"
    
    /// Image understanding support.
    case vision = "Vision/Image Analysis"
    
    /// Incremental response streaming support.
    case streaming = "Response Streaming"
    
} 
