import Foundation
import CryptoKit

// MARK: - Core Tool Protocols

/// Provider-neutral definition of a tool that can be exposed to models.
public protocol AITool {
    var name: String { get }
    var description: String { get }
    var parameters: any AIToolParameters { get }
}

/// Optional user/runtime configuration for tools.
protocol ConfigurableAITool: AITool {
    var configurationSchema: any AIToolParameters { get }
    func defaultConfiguration() -> [String: JSONValue]
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

struct ToolExecutionContext {
    var conversation: ConversationItem
    var turn: ConversationTurn
}

struct ToolExecutionCall {
    var id: String
    var name: String
    var argumentsJSON: String
    var configuration: [String: JSONValue]
    var context: ToolExecutionContext
}

/// Protocol for tools that can be executed.
/// Executable tools implement the actual functionality that will be performed
/// when the AI invokes the tool.
protocol ExecutableTool: AITool {
    func execute(_ call: ToolExecutionCall) async throws -> String
}

// MARK: - Generic Implementations

/// A generic implementation of the AITool protocol that can be used directly or subclassed.
/// This provides a standard way to define tools with their parameters and descriptions.
struct GenericTool: AITool, Codable {
    let name: String
    let description: String
    private let _parameters: GenericToolParameters

    var parameters: any AIToolParameters { _parameters }

    /// Create a new generic tool
    /// - Parameters:
    ///   - name: Unique identifier for the tool
    ///   - description: Human-readable description of the tool
    ///   - parameters: Parameters schema for the tool
    init(name: String, description: String, parameters: GenericToolParameters) {
        self.name = name
        self.description = description
        self._parameters = parameters
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case _parameters = "parameters"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        _parameters = try container.decode(GenericToolParameters.self, forKey: ._parameters)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(_parameters, forKey: ._parameters)
    }
}

/// A generic implementation of the AIToolParameters protocol.
/// Defines the structure for tool parameters using a JSON Schema-like format.
struct GenericToolParameters: AIToolParameters, Codable {
    let type: String = "object"
    private let _properties: [String: GenericToolProperty]
    let required: [String]?

    var properties: [String: any AIToolProperty] { _properties }

    /// Create a new parameters schema for a tool
    /// - Parameters:
    ///   - properties: Dictionary of parameter names to their property definitions
    ///   - required: Optional array of parameter names that are required
    init(properties: [String: GenericToolProperty], required: [String]? = nil) {
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
struct GenericToolProperty: AIToolProperty, Codable {
    let type: String
    let description: String
    let enumValues: [String]?

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
    init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    var enumerated: [String]? {
        get { enumValues }
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
