import Foundation

enum OpenAICompatibleEncoding {
    enum ResponseFormatTarget {
        case chatCompletions
        case responses
    }

    static func applyOptions(
        _ options: LLMGenerationOptions,
        to body: inout [String: JSONValue],
        maxTokenKey: String,
        responseFormatTarget: ResponseFormatTarget,
        includeStop: Bool
    ) throws {
        var providerExtras = options.providerExtras
        if let temperature = options.temperature { body["temperature"] = .number(temperature) }
        if let topP = options.topP { body["top_p"] = .number(topP) }
        if let maxOutputTokens = options.maxOutputTokens { body[maxTokenKey] = .integer(maxOutputTokens) }
        if includeStop && !options.stop.isEmpty {
            body["stop"] = .array(options.stop.map { .string($0) })
        }

        switch (responseFormatTarget, options.responseFormat) {
        case (_, .text):
            break
        case (.chatCompletions, .jsonObject):
            body["response_format"] = .object(["type": .string("json_object")])
        case (.chatCompletions, .jsonSchema):
            body["response_format"] = .object([
                "type": .string("json_schema"),
                "json_schema": .object(try jsonSchemaPayload(from: &providerExtras))
            ])
        case (.responses, .jsonObject):
            body["text"] = .object(["format": .object(["type": .string("json_object")])])
        case (.responses, .jsonSchema):
            var format = try jsonSchemaPayload(from: &providerExtras)
            format["type"] = .string("json_schema")
            body["text"] = .object(["format": .object(format)])
        }

        if responseFormatTarget == .responses {
            if let reasoning = options.reasoning {
                body["reasoning"] = .object(["effort": .string(reasoning)])
            }
            if let serviceTier = options.serviceTier {
                body["service_tier"] = .string(serviceTier)
            }
        }

        for (key, value) in providerExtras {
            body[key] = value
        }
    }

    static func applyMappedOptions(
        _ options: LLMGenerationOptions,
        to body: inout [String: JSONValue],
        mappings: [LLMParameterID: LLMParameterMappingDescriptor]
    ) throws {
        var providerExtras = options.providerExtras
        for mapping in mappings.values where mapping.isEnabled {
            guard let value = options.jsonValue(for: mapping.semanticParameterID) ?? mapping.defaultValue else {
                if mapping.isRequired {
                    throw LLMProviderError.unsupportedParameter("\(mapping.semanticParameterID.rawValue) is required.")
                }
                continue
            }

            switch mapping.encodingKind {
            case .scalarKey:
                guard !mapping.wireKey.isEmpty else {
                    throw LLMProviderError.unsupportedParameter("\(mapping.semanticParameterID.rawValue) has no wire key.")
                }
                body[mapping.wireKey] = value
            case .structuredPreset:
                try applyStructuredPreset(mapping.structuredPreset, value: value, providerExtras: &providerExtras, to: &body)
            case .disabled:
                continue
            }
        }

        for (key, value) in providerExtras {
            body[key] = value
        }
    }

    private static func applyStructuredPreset(
        _ preset: ModelParameterStructuredPreset?,
        value: JSONValue,
        providerExtras: inout [String: JSONValue],
        to body: inout [String: JSONValue]
    ) throws {
        guard let preset else { return }
        switch preset {
        case .openAIChatResponseFormat:
            switch value.stringValue {
            case "json_object", "jsonObject":
                body["response_format"] = .object(["type": .string("json_object")])
            case "json_schema", "jsonSchema":
                body["response_format"] = .object([
                    "type": .string("json_schema"),
                    "json_schema": .object(try jsonSchemaPayload(from: &providerExtras))
                ])
            default:
                break
            }
        case .openAIResponsesTextFormat:
            switch value.stringValue {
            case "json_object", "jsonObject":
                body["text"] = .object(["format": .object(["type": .string("json_object")])])
            case "json_schema", "jsonSchema":
                var format = try jsonSchemaPayload(from: &providerExtras)
                format["type"] = .string("json_schema")
                body["text"] = .object(["format": .object(format)])
            default:
                break
            }
        case .openAIResponsesReasoning:
            if let effort = value.stringValue, !effort.isEmpty {
                body["reasoning"] = .object(["effort": .string(effort)])
            }
        }
    }

    private static func jsonSchemaPayload(from providerExtras: inout [String: JSONValue]) throws -> [String: JSONValue] {
        guard let value = providerExtras.removeValue(forKey: "json_schema"),
              let object = value.objectValue else {
            throw LLMProviderError.unsupportedParameter("response_format json_schema requires providerExtras.json_schema object.")
        }
        return object
    }

    static func chatTools(from tools: [LLMToolDefinition]) -> [JSONValue] {
        tools.map { tool in
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": tool.parameters
                ])
            ])
        }
    }

    static func chatContent(from message: LLMMessage) throws -> JSONValue {
        let parts = message.content
        if isPlainText(parts) {
            return .string(message.displayText)
        }

        return .array(try parts.map { part in
            switch part.kind {
            case .text, .reasoning, .toolResult:
                return .object(["type": .string("text"), "text": .string(part.text ?? "")])
            case .image:
                guard let url = imageURL(from: part) else {
                    throw LLMProviderError.unsupportedParameter("OpenAI Chat image content requires sourceURL or dataBase64.")
                }
                return .object([
                    "type": .string("image_url"),
                    "image_url": .object(["url": .string(url)])
                ])
            case .file:
                guard let data = fileData(from: part) else {
                    throw LLMProviderError.unsupportedParameter("OpenAI Chat file content requires dataBase64.")
                }
                return .object([
                    "type": .string("file"),
                    "file": .object([
                        "filename": .string(filename(from: part)),
                        "file_data": .string(data)
                    ])
                ])
            case .audio:
                throw LLMProviderError.unsupportedParameter("OpenAI Chat audio content is not supported by this adapter.")
            }
        })
    }

    static func responsesContent(from message: LLMMessage) throws -> JSONValue {
        let parts = message.content
        if isPlainText(parts) {
            return .string(message.displayText)
        }

        return .array(try parts.map { part in
            switch part.kind {
            case .text, .reasoning, .toolResult:
                return .object(["type": .string("input_text"), "text": .string(part.text ?? "")])
            case .image:
                guard let url = imageURL(from: part) else {
                    throw LLMProviderError.unsupportedParameter("OpenAI Responses image content requires sourceURL or dataBase64.")
                }
                return .object([
                    "type": .string("input_image"),
                    "image_url": .string(url),
                    "detail": .string("auto")
                ])
            case .file:
                var file: [String: JSONValue] = ["type": .string("input_file")]
                if let data = fileData(from: part) {
                    file["file_data"] = .string(data)
                    file["filename"] = .string(filename(from: part))
                } else if let url = part.sourceURL {
                    file["file_url"] = .string(url)
                } else {
                    throw LLMProviderError.unsupportedParameter("OpenAI Responses file content requires sourceURL or dataBase64.")
                }
                return .object(file)
            case .audio:
                throw LLMProviderError.unsupportedParameter("OpenAI Responses audio content is not supported by this adapter.")
            }
        })
    }

    static func responsesTools(from tools: [LLMToolDefinition]) -> [JSONValue] {
        tools.map { tool in
            .object([
                "type": .string("function"),
                "name": .string(tool.name),
                "description": .string(tool.description),
                "parameters": tool.parameters
            ])
        }
    }

    static func usage(from object: [String: JSONValue], inputKey: String, outputKey: String) -> LLMUsage {
        LLMUsage(
            inputTokens: object.int(inputKey),
            outputTokens: object.int(outputKey),
            totalTokens: object.int("total_tokens")
        )
    }

    private static func imageURL(from part: LLMContentPart) -> String? {
        if let sourceURL = part.sourceURL, !sourceURL.isEmpty { return sourceURL }
        guard let data = part.dataBase64, !data.isEmpty else { return nil }
        return "data:\(part.mimeType ?? "image/png");base64,\(data)"
    }

    private static func fileData(from part: LLMContentPart) -> String? {
        guard let data = part.dataBase64, !data.isEmpty else { return nil }
        if data.hasPrefix("data:") { return data }
        return "data:\(part.mimeType ?? "application/octet-stream");base64,\(data)"
    }

    private static func isPlainText(_ parts: [LLMContentPart]) -> Bool {
        parts.allSatisfy { part in
            switch part.kind {
            case .text, .reasoning, .toolResult:
                return true
            case .image, .audio, .file:
                return false
            }
        }
    }

    private static func filename(from part: LLMContentPart) -> String {
        guard let sourceURL = part.sourceURL,
              let url = URL(string: sourceURL),
              !url.lastPathComponent.isEmpty else {
            return "input_file"
        }
        return url.lastPathComponent
    }
}
