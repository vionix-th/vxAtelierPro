import Foundation

/// Provider-neutral definition of a tool that can be exposed to models.
public protocol LLMTool {
    var name: String { get }
    var description: String { get }
    var parameters: any LLMToolParameters { get }
}

/// Represents the parameters schema for a tool.
/// Defines the structure, types, and constraints for parameters that a tool accepts.
/// This follows a JSON Schema-like format that most LLM providers understand.
public protocol LLMToolParameters {
    /// The parameter container type (typically "object")
    var type: String { get }

    /// Dictionary mapping parameter names to their property definitions
    var properties: [String: any LLMToolProperty] { get }

    /// Array of parameter names that are required (can be nil if none are required)
    var required: [String]? { get }
}

/// Represents a single parameter property.
public protocol LLMToolProperty {
    /// The data type of this parameter (e.g., "string", "number", "boolean")
    var type: String { get }

    /// Human-readable description of the parameter
    var description: String { get }

    /// Possible values if this is an enumerated parameter
    var enumValues: [String]? { get }

    /// Alias for providers that expect this JSON Schema key name.
    var enumerated: [String]? { get }
}

/// A generic implementation of the LLMTool protocol.
struct GenericLLMTool: LLMTool, Codable {
    let name: String
    let description: String
    private let _parameters: GenericLLMToolParameters

    var parameters: any LLMToolParameters { _parameters }

    init(name: String, description: String, parameters: GenericLLMToolParameters) {
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
        _parameters = try container.decode(GenericLLMToolParameters.self, forKey: ._parameters)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(_parameters, forKey: ._parameters)
    }
}

/// A generic implementation of the LLMToolParameters protocol.
struct GenericLLMToolParameters: LLMToolParameters, Codable {
    let type: String = "object"
    private let _properties: [String: GenericLLMToolProperty]
    let required: [String]?

    var properties: [String: any LLMToolProperty] { _properties }

    init(properties: [String: GenericLLMToolProperty], required: [String]? = nil) {
        self._properties = properties
        self.required = required
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case _properties = "properties"
        case required
    }
}

/// A generic implementation of the LLMToolProperty protocol.
struct GenericLLMToolProperty: LLMToolProperty, Codable {
    let type: String
    let description: String
    let enumValues: [String]?

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }

    init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    var enumerated: [String]? { enumValues }
}
