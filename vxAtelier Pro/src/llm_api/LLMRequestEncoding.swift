import Foundation

/// Helpers for converting tool schemas into provider-neutral LLM request values.
enum LLMRequestEncoding {
    /// Wraps an object literal as a `JSONValue` without exposing call sites to enum case syntax.
    static func jsonObject(_ object: [String: JSONValue]) -> JSONValue {
        .object(object)
    }

    /// Builds the JSON-schema-like parameter object shared by provider adapters.
    static func toolSchema(from tool: LLMTool) -> JSONValue {
        let properties = Dictionary(uniqueKeysWithValues: tool.parameters.properties.map { name, property in
            var body: [String: JSONValue] = [
                "type": .string(property.type),
                "description": .string(property.description)
            ]
            if let values = property.enumValues ?? property.enumerated {
                body["enum"] = .array(values.map { .string($0) })
            }
            return (name, JSONValue.object(body))
        })
        var schema: [String: JSONValue] = [
            "type": .string(tool.parameters.type),
            "properties": .object(properties)
        ]
        if let required = tool.parameters.required {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    /// Converts a tool into a provider-neutral LLM tool definition.
    static func toolDefinition(from tool: LLMTool) -> LLMToolDefinition {
        LLMToolDefinition(name: tool.name, description: tool.description, parameters: toolSchema(from: tool))
    }
}
