import Foundation
import SwiftData
import CryptoKit  // Add this import for MD5

// MARK: - Core Tool Protocols

/// Represents a function/tool that can be called by AI services.
/// Tools define capabilities that AI models can use to perform tasks within the application.
/// Each tool has a name, description, and parameter schema that the AI uses to execute functions.
public protocol AITool {
    /// Unique identifier for the tool
    var name: String { get }
    
    /// Human-readable description of what the tool does
    var description: String { get }
    
    /// Schema defining the parameters this tool accepts
    var parameters: any AIToolParameters { get }
    
    /// Returns the default configuration for this tool
    /// - Returns: A dictionary of configuration values or nil if no configuration is needed
    func getDefaultConfiguration() -> [String: Any]?
}

/// Represents the parameters schema for a tool.
/// Defines the structure, types, and constraints for parameters that a tool accepts.
/// This follows a JSON Schema-like format that most AI providers understand.
public protocol AIToolParameters {
    /// The parameter container type (typically "object")
    var type: String { get }
    
    /// Dictionary mapping parameter names to their property definitions
    var properties: [String: any AIToolProperty] { get }
    
    /// Array of parameter names that are required (can be nil if none are required)
    var required: [String]? { get }
}

/// Represents a single parameter property for a tool.
/// Defines the type, description, and possible enumerated values for a parameter.
public protocol AIToolProperty {
    /// The data type of this parameter (e.g., "string", "number", "boolean")
    var type: String { get }
    
    /// Human-readable description of the parameter
    var description: String { get }
    
    /// Possible values if this is an enumerated parameter
    var enumValues: [String]? { get }
    
    /// Alias for providers that expect this JSON Schema key name.
    var enumerated: [String]? { get }
}

/// Represents a tool call made by the AI.
/// When an AI invokes a tool, it provides an ID, name, and arguments to execute the function.
public protocol AIToolCall: Codable {
    /// Unique identifier for this specific tool call
    var id: String { get }
    
    /// Name of the tool being called (must match a registered tool)
    var name: String { get }
    
    /// JSON string containing the arguments for the tool call
    var arguments: String { get }
    
    /// Optional configuration and context for the tool call.
    /// This is not included in serialization/deserialization
    /// and can be used to pass runtime information.
    var context: Any? { get set }
    
    /// Optional configuration dictionary for customizing tool behavior
    /// This is not included in serialization/deserialization
    var configuration: [String: Any]? { get set }
}

/// Represents a tool call result.
/// After a tool is executed, it returns a result that must be sent back to the AI.
public protocol AIToolCallResult: Codable {
    /// ID of the tool call this result is responding to
    var toolCallId: String { get }
    
    /// Output of the tool execution as a string (typically JSON)
    var output: String { get }
}

// MARK: - Tool Handler

/// Protocol for handling tool calls from AI services.
/// Tool handlers are responsible for:
/// 1. Finding appropriate tool implementations
/// 2. Executing tools with provided arguments
/// 3. Formatting and returning results
public protocol AIToolHandler {
    /// Handle tool calls and return results
    /// - Parameters:
    ///   - toolCalls: Array of tool calls to execute
    /// - Returns: Array of tool call results
    /// - Throws: Provider or tool execution errors
    func handleToolCalls(_ toolCalls: [AIToolCall]) async throws -> [AIToolCallResult]
}

/// Protocol for tools that can be executed.
/// Executable tools implement the actual functionality that will be performed
/// when the AI invokes the tool.
public protocol ExecutableTool: AITool {
    /// Execute the tool with the given arguments and optional configuration
    /// - Parameters:
    ///   - arguments: The arguments as a JSON string
    ///   - configuration: Optional configuration for the tool execution
    ///   - context: Optional context information for the execution
    /// - Returns: The result of the execution as a string
    /// - Throws: Errors that might occur during execution
    func execute(arguments: String, configuration: [String: Any]?, context: Any?) async throws -> String
}

/// Default implementation of AIToolHandler using AIToolRegistry.
/// This handler manages the process of finding tools in the registry,
/// executing them, and formatting results to return to the AI.
public class DefaultToolHandler: AIToolHandler {
    private let registry: AIToolRegistry
    
    /// Initialize with a tool registry
    /// - Parameter registry: The registry containing available tools, defaults to shared instance
    public init(registry: AIToolRegistry = .shared) {
        self.registry = registry
    }
    
    public func handleToolCalls(_ toolCalls: [AIToolCall]) async throws -> [AIToolCallResult] {
        var results: [AIToolCallResult] = []
        
        for toolCall in toolCalls {
            // Get the tool from registry
            guard let tool = registry.getTools().first(where: { $0.name == toolCall.name }) else {
                throw LLMProviderError.unsupportedCapability("Tool not found: \(toolCall.name)")
            }                        
            
            // Execute the tool if it supports execution
            if let executableTool = tool as? any ExecutableTool {                
                let result = try await executableTool.execute(
                    arguments: toolCall.arguments,
                    configuration: toolCall.configuration,
                    context: toolCall.context
                )
                results.append(GenericToolCallResult(
                    toolCallId: toolCall.id,
                    output: result
                ))
            } else {
                results.append(GenericToolCallResult(
                    toolCallId: toolCall.id,
                    output: "Tool execution not supported"
                ))
            }
        }
        
        return results
    }
}

// MARK: - Generic Implementations

/// A generic implementation of the AITool protocol that can be used directly or subclassed.
/// This provides a standard way to define tools with their parameters and descriptions.
public struct GenericTool: AITool, Codable {
    public let name: String
    public let description: String
    private let _parameters: GenericToolParameters
    
    public var parameters: any AIToolParameters { _parameters }
    
    /// Create a new generic tool
    /// - Parameters:
    ///   - name: Unique identifier for the tool
    ///   - description: Human-readable description of the tool
    ///   - parameters: Parameters schema for the tool
    public init(name: String, description: String, parameters: GenericToolParameters) {
        self.name = name
        self.description = description
        self._parameters = parameters
    }
    
    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case _parameters = "parameters"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        _parameters = try container.decode(GenericToolParameters.self, forKey: ._parameters)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(_parameters, forKey: ._parameters)
    }
    
    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}

/// A generic implementation of the AIToolParameters protocol.
/// Defines the structure for tool parameters using a JSON Schema-like format.
public struct GenericToolParameters: AIToolParameters, Codable {
    public let type: String = "object"
    private let _properties: [String: GenericToolProperty]
    public let required: [String]?
    
    public var properties: [String: any AIToolProperty] { _properties }
    
    /// Create a new parameters schema for a tool
    /// - Parameters:
    ///   - properties: Dictionary of parameter names to their property definitions
    ///   - required: Optional array of parameter names that are required
    public init(properties: [String: GenericToolProperty], required: [String]? = nil) {
        self._properties = properties
        self.required = required
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case _properties = "properties"
        case required
    }
}

/// A generic implementation of the AIToolProperty protocol.
/// Defines a single parameter property with its type, description, and possible values.
public struct GenericToolProperty: AIToolProperty, Codable {
    public let type: String
    public let description: String
    public let enumValues: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
    
    /// Create a new parameter property
    /// - Parameters:
    ///   - type: The data type of this parameter (e.g., "string", "number", "boolean")
    ///   - description: Human-readable description of the parameter
    ///   - enumValues: Optional array of possible values for enumerated parameters
    public init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
    
    public var enumerated: [String]? {
        get { enumValues }
    }
}

/// A generic implementation of the AIToolCall protocol.
/// Represents a tool call from an AI with its ID, name, and arguments.
public struct GenericToolCall: AIToolCall {
    public let id: String
    public let name: String
    public let arguments: String
    public var configuration: [String: Any]?
    public var context: Any?
    
    /// Create a new tool call
    /// - Parameters:
    ///   - id: Unique identifier for this specific tool call
    ///   - name: Name of the tool being called
    ///   - arguments: JSON string containing the arguments for the tool call
    ///   - configuration: Optional configuration for the tool execution
    ///   - context: Optional context information for the execution
    public init(id: String, name: String, arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.configuration = configuration
        self.context = context
    }
    
    // Custom Codable implementation to exclude configuration from serialization
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case arguments
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        arguments = try container.decode(String.self, forKey: .arguments)
        configuration = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(arguments, forKey: .arguments)
        // configuration and context are intentionally not encoded
    }
}

/// A generic implementation of the AIToolCallResult protocol.
/// Represents the result of executing a tool call.
public struct GenericToolCallResult: AIToolCallResult {
    public let toolCallId: String
    public let output: String
    
    /// Create a new tool call result
    /// - Parameters:
    ///   - toolCallId: ID of the tool call this result is responding to
    ///   - output: Output of the tool execution as a string
    public init(toolCallId: String, output: String) {
        self.toolCallId = toolCallId
        self.output = output
    }
}

/// Provides a stable hash implementation using MD5.
/// Used to generate consistent identifiers for tool calls and other components.
extension String {
    /// Computes an MD5 hash of the string and returns it as a hexadecimal string.
    /// This provides a stable identifier that remains the same for identical inputs.
    /// - Returns: MD5 hash as a hexadecimal string
    func stableHash() -> String {
        let data = Data(self.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}
