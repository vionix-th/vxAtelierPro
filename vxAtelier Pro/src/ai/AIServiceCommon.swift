import Foundation

// MARK: - Common Types 
public struct GenericConfiguration: AIServiceConfiguration {
    public var apiKey: String
    public var baseURL: String
    public var chatCompletionsEndpoint: String
    public var modelsEndpoint: String
    
    public init(
        apiKey: String,
        baseURL: String,
        chatCompletionsEndpoint: String,
        modelsEndpoint: String
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.chatCompletionsEndpoint = chatCompletionsEndpoint
        self.modelsEndpoint = modelsEndpoint
    }
    
    /// Initialize from an APIConfigurationItem
    init(config: APIConfigurationItem) {
        self.apiKey = config.apiKey
        self.baseURL = config.baseURL
        self.chatCompletionsEndpoint = config.chatCompletionsEndpoint
        self.modelsEndpoint = config.modelsEndpoint
    }
}

// MARK: - Common Utility Extensions

/// Utility extensions for token counting and other common operations
extension Array where Element == AIChatMessage {
    /// Estimate the total tokens in a conversation
    /// Note: This is a simplified estimation and might not be accurate for all models
    func estimatedTokenCount() -> Int {
        let baseOverhead = 3
        return reduce(baseOverhead) { result, message in
            // Very rough token estimation (4 chars = ~1 token)
            let wordCount = message.content.split(separator: " ").count
            let charCount = message.content.count
            
            let charBasedEstimate = charCount / 4
            let wordBasedEstimate = Int(Double(wordCount) / 0.75)
            let metadataTokens = 4
            
            return result + Swift.max(charBasedEstimate, wordBasedEstimate) + metadataTokens
        }
    }
    
    /// Alias for estimatedTokenCount to maintain compatibility with existing code
    public func totalTokens() -> Int {
        return estimatedTokenCount()
    }
}

/// A generic implementation of AIChatMessage for use throughout the application
public struct GenericChatMessage: AIChatMessage {
    public var role: String
    public var content: String
    public var toolCalls: [AIToolCall]?
    public var toolCallId: String?
    
    public init(role: String, content: String, toolCalls: [AIToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

/// A generic implementation of the AIChatCompletionRequest protocol
public struct GenericChatCompletionRequest: AIChatCompletionRequest {
    public var messages: [AIChatMessage]
    public var tools: [AITool]?
    public var toolChoice: String?
    public private(set) var parameters: [String: Any] = [:]
    
    public init(messages: [AIChatMessage], tools: [AITool]? = nil, toolChoice: String? = nil) {
        self.messages = messages
        self.tools = tools
        // Only set toolChoice if we have tools
        self.toolChoice = tools != nil && !tools!.isEmpty ? toolChoice : nil
    }
    
    public func getParameter(_ name: String) -> Any? {
        return parameters[name]
    }
    
    public mutating func setParameter(name: String, value: Any) {
        parameters[name] = value
    }
    
    public func getAllParameters() -> [String: Any] {
        return parameters
    }
}

/// A Generic implementation of the AIChatCompletionResponse protocol
public struct GenericChatCompletionResponse: AIChatCompletionResponse {
    public var content: String?
    public var toolCalls: [AIToolCall]?
    
    public init(content: String, toolCalls: [AIToolCall]? = nil) {
        self.content = content
        self.toolCalls = toolCalls
    }
}

/// Represents a chunk of a chat completion, supporting both streaming and non-streaming modes
public struct AIChatCompletionChunk {
    public let content: String?
    public let toolCalls: [AIToolCall]?
    public let isFinal: Bool

    public init(content: String? = nil, toolCalls: [AIToolCall]? = nil, isFinal: Bool = false) {
        self.content = content
        self.toolCalls = toolCalls
        self.isFinal = isFinal
    }
}
