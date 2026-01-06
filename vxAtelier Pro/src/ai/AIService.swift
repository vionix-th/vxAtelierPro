import Foundation

// MARK: - Core Protocols

/// Represents an AI service provider that can handle chat completions and model fetching.
/// This protocol serves as the main interface for interacting with different AI providers like OpenAI, Anthropic, etc.
/// 
/// Implementations should:
/// - Handle provider-specific API authentication and endpoints
/// - Manage chat completion services through the `chat` property
/// - Support model discovery and parameter configuration
/// - Convert between generic and provider-specific request/response formats
public protocol AIService {
    /// The chat completion service for this AI provider.
    /// Typically implemented as a lazy var to avoid circular dependencies.
    /// Each provider should have its own chat service implementation.
    var chat: AIChatCompletionServiceStreamable { get }
    
    /// Fetches available models from the AI provider.
    /// This method should handle provider-specific authentication and response formats.
    /// - Returns: Array of AI models supported by the provider
    /// - Throws: AIServiceError for network, authentication, or parsing failures
    func fetchAvailableModels() async throws -> [AIModel]

    /// Returns the provider's default model catalog with baked-in metadata
    /// (context window, capabilities, identifiers). Used as a baseline for
    /// merging with live provider listings and for offline/default UX.
    func getDefaultModels() -> [AIModel]
    
    /// Returns default request parameters supported by this provider.
    /// These parameters are used to configure model behavior (temperature, tokens, etc).
    /// Each provider should define appropriate parameter ranges and defaults.
    /// - Returns: Array of parameter specifications with provider-specific defaults
    func getDefaultParameters() -> [AiRequestArgument]
    
    /// Applies parameters from request options to a provider-specific request format.
    /// This method should handle conversion between generic and provider-specific parameter formats.
    /// - Parameters:
    ///   - request: The generic request to modify (typically GenericChatCompletionRequest)
    ///   - parameters: The parameters to apply (from getDefaultParameters)
    /// - Returns: Modified request with provider-specific parameters applied
    func applyParameters(to request: Any, from parameters: [AiRequestArgument]) -> Any
}

/// Represents a single message in a chat conversation
public protocol AIChatMessage {
    /// The role of the sender (e.g., "user", "assistant", "system")
    var role: String { get }
    
    /// The content of the message
    var content: String { get }
    
    /// Optional tool calls made by assistant
    var toolCalls: [AIToolCall]? { get }
    
    /// Optional reference to tool call being responded to
    var toolCallId: String? { get }
}

/// Represents a chat completion request to be sent to an AI service
public protocol AIChatCompletionRequest {
    /// The messages in the conversation
    var messages: [AIChatMessage] { get }
    
    /// Available tools for the model to use
    var tools: [AITool]? { get set }
    
    /// Tool choice configuration
    var toolChoice: String? { get set }
    
    /// Get a parameter value by name
    /// - Parameter name: The name of the parameter
    /// - Returns: The parameter value, if it exists
    func getParameter(_ name: String) -> Any?
    
    /// Get all parameters
    /// - Returns: Dictionary of all parameters
    func getAllParameters() -> [String: Any]
    
    /// Set a parameter value
    /// - Parameters:
    ///   - name: The name of the parameter
    ///   - value: The value to set
    mutating func setParameter(name: String, value: Any)
}

/// Represents a response from an AI service's chat completion
public protocol AIChatCompletionResponse {
    /// The generated content from the AI
    var content: String? { get }
    
    /// Tool calls made by the AI
    var toolCalls: [AIToolCall]? { get }
}

/// Service that provides chat completion functionality.
/// This protocol defines the unified chat interaction method for all providers.
public protocol AIChatCompletionServiceStreamable {
    /// The service configuration.
    /// Typically holds provider-specific settings like API keys and endpoints.
    var configuration: Any { get }
    
    /// Available tools registered with this service.
    /// Tools allow the AI to perform actions through function calling.
    var availableTools: [AITool] { get }
    
    /// Creates a message appropriate for this service.
    /// Implementations should handle conversion between generic and provider-specific message formats.
    func createMessage(role: String, content: String, toolCalls: [AIToolCall]?, toolCallId: String?) -> AIChatMessage
    
    /// Creates a request appropriate for this service from messages.
    func createRequest(messages: [AIChatMessage]) -> AIChatCompletionRequest
    
    /// Register available tools for the service.
    func registerTools(_ tools: [AITool])
    
    /// Unified completion method: always returns a stream of chunks.
    func completeStream(
        request: AIChatCompletionRequest
    ) -> AsyncThrowingStream<AIChatCompletionChunk, Error>
}

/// Represents an AI model from a provider
public protocol AIModel {
    /// The model identifier
    var id: String { get }
    
    /// The provider of the model
    var provider: String { get }    
    
    /// Capabilities the model supports (text, vision, etc.)
    var capabilities: [ModelCapability] { get }
    
    /// Maximum context size in tokens that this model supports
    var contextSize: Int { get }
}

// MARK: - Error Types

/// Errors that can occur when using AI services
public enum AIServiceError: Error, LocalizedError {
    case invalidURL
    case invalidAPIKey
    case invalidResponse
    case networkError(Error)      // For actual network connectivity issues
    case protocolError(Error)     // For HTTP/API protocol level errors
    case noCompletionAvailable
    case noConfiguration
    case contextLimitExceeded(maxTokens: Int, actualTokens: Int)
    case unsupportedOperation(String)
    case invalidConfiguration
    case apiError(message: String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL configuration."
        case .invalidAPIKey: return "Invalid API key."
        case .invalidResponse: return "Invalid response from the AI service."
        case .networkError(let error): 
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return "No internet connection available."
                case .timedOut:
                    return "Request timed out. Please try again."
                case .cannotFindHost:
                    return "Cannot find the AI service host."
                case .cannotConnectToHost:
                    return "Cannot connect to the AI service."
                case .badServerResponse:
                    return "Server returned an invalid response."
                case .unsupportedURL:
                    return "The API endpoint is not supported."
                case .dataNotAllowed:
                    return "Data transfer is not allowed."
                case .httpTooManyRedirects:
                    return "Too many redirects."
                default:
                    return "Network error: \(urlError.localizedDescription)"
                }
            }
            return error.localizedDescription
        case .protocolError(let error):
            return "Protocol error: \(error.localizedDescription)"
        case .noCompletionAvailable: return "No completion available from the AI service."
        case .noConfiguration: return "No API configuration available."
        case .contextLimitExceeded(let max, let actual): return "Context limit exceeded (max: \(max), actual: \(actual))"
        case .unsupportedOperation(let message): return message
        case .invalidConfiguration: return "Invalid service configuration."
        case .apiError(let message): return message
        }
    }
}

/// Base protocol for AI service configuration
public protocol AIServiceConfiguration {
    var apiKey: String { get }
    var baseURL: String { get }
}

/// Generic API configuration structure for AI services
public struct GenericAPIConfiguration: AIServiceConfiguration {
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
        vxAtelierPro.log.debug("Initializing with baseURL: \(baseURL)")
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.chatCompletionsEndpoint = chatCompletionsEndpoint
        self.modelsEndpoint = modelsEndpoint
    }
}

// MARK: - Extension Methods

/// Extension to AIChatMessage for token counting
extension AIChatMessage {
    /// Estimates the token count for this message
    public func estimatedTokenCount() -> Int {
        let wordCount = content.split(separator: " ").count
        let charCount = content.count
        
        let charBasedEstimate = charCount / 4
        let wordBasedEstimate = Int(Double(wordCount) / 0.75)
        let metadataTokens = 4
        let estimatedTokens = max(charBasedEstimate, wordBasedEstimate) + metadataTokens
                
        return estimatedTokens
    }
}
