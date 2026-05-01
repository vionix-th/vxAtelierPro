import Foundation

enum LLMRequestEncoding {
    static func jsonObject(_ object: [String: JSONValue]) -> JSONValue {
        .object(object)
    }

    static func toolSchema(from tool: AITool) -> JSONValue {
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

    static func llmTool(from tool: AITool) -> LLMTool {
        LLMTool(name: tool.name, description: tool.description, parameters: toolSchema(from: tool))
    }
}
