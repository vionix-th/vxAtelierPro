import Foundation

/// Provider-neutral definition of a tool that can be exposed to models.
public protocol LLMTool {
    /// Provider-visible unique function name.
    var name: String { get }
    /// Provider-visible tool description used for model selection.
    var description: String { get }
    /// JSON-schema-like input contract for the tool.
    var parameters: any LLMToolParameters { get }
}

/// JSON-schema-like parameter container accepted by provider adapters.
public protocol LLMToolParameters {
    /// Parameter container type, normally `object`.
    var type: String { get }

    /// Parameter definitions keyed by provider-visible argument name.
    var properties: [String: any LLMToolProperty] { get }

    /// Required provider-visible argument names, or `nil` when all arguments are optional.
    var required: [String]? { get }
}

/// JSON-schema-like definition for one tool argument.
public protocol LLMToolProperty {
    /// Provider-visible primitive type such as `string`, `number`, or `boolean`.
    var type: String { get }

    /// Provider-visible argument description used by the model.
    var description: String { get }

    /// Allowed values for enumerated arguments.
    var enumValues: [String]? { get }

    /// Alias for providers that expect this JSON Schema key name.
    var enumerated: [String]? { get }
}

/// Codable tool implementation used for imported or dynamically constructed schemas.
struct GenericLLMTool: LLMTool, Codable {
    let name: String
    let description: String
    private let _parameters: GenericLLMToolParameters

    /// Exposes decoded parameters through the existential protocol shape.
    var parameters: any LLMToolParameters { _parameters }

    /// Creates a generic tool from a concrete parameter schema.
    init(name: String, description: String, parameters: GenericLLMToolParameters) {
        self.name = name
        self.description = description
        self._parameters = parameters
    }

    /// Codable keys that store the concrete parameters behind the protocol property.
    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case _parameters = "parameters"
    }

    /// Decodes the concrete parameter schema stored behind the protocol requirement.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        _parameters = try container.decode(GenericLLMToolParameters.self, forKey: ._parameters)
    }

    /// Encodes the concrete parameter schema under the provider-facing `parameters` key.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(_parameters, forKey: ._parameters)
    }
}

/// Codable object-parameter schema for generic LLM tools.
struct GenericLLMToolParameters: LLMToolParameters, Codable {
    let type: String = "object"
    private let _properties: [String: GenericLLMToolProperty]
    let required: [String]?

    /// Exposes concrete properties through the existential protocol shape.
    var properties: [String: any LLMToolProperty] { _properties }

    /// Creates an object schema from concrete properties and optional required keys.
    init(properties: [String: GenericLLMToolProperty], required: [String]? = nil) {
        self._properties = properties
        self.required = required
    }

    /// Codable keys that store concrete properties behind the protocol property.
    private enum CodingKeys: String, CodingKey {
        case type
        case _properties = "properties"
        case required
    }
}

/// Codable property schema for generic LLM tool arguments.
struct GenericLLMToolProperty: LLMToolProperty, Codable {
    let type: String
    let description: String
    let enumValues: [String]?

    /// Codable keys for JSON Schema property fields.
    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }

    /// Creates a generic argument schema with optional enum constraints.
    init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    /// Mirrors `enumValues` for providers that use an `enumerated` access point.
    var enumerated: [String]? { enumValues }
}
