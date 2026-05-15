import Foundation

/// Shared request encoders for OpenAI and OpenAI-compatible wire formats.
enum OpenAICompatibleEncoding {
    /// Chat body keys that caller-provided provider extras must not override.
    static let chatReservedProviderExtraKeys: Set<String> = [
        "model", "messages", "stream", "tools", "tool_choice", "response_format", "json_schema"
    ]
    /// Responses body keys that caller-provided provider extras must not override.
    static let responsesReservedProviderExtraKeys: Set<String> = [
        "model", "input", "instructions", "stream", "tools", "text", "reasoning", "json_schema"
    ]

    /// Applies scalar mappings, structured presets, and safe provider extras to a request body.
    static func applyMappedOptions(
        _ options: LLMGenerationOptions,
        to body: inout [String: JSONValue],
        mappings: [LLMParameterID: LLMParameterMappingDescriptor],
        reservedProviderExtraKeys: Set<String> = []
    ) throws {
        var providerExtras = options.providerExtras
        for mapping in mappings.values {
            guard let value = options.jsonValue(for: mapping.semanticParameterID) else { continue }
            providerExtras.removeValue(forKey: mapping.semanticParameterID.rawValue)

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
            guard !reservedProviderExtraKeys.contains(key), body[key] == nil else {
                throw LLMProviderError.unsupportedParameter("providerExtras.\(key) cannot override a reserved request field.")
            }
            body[key] = value
        }
    }

    /// Encodes provider-specific structured parameters that need nested request bodies.
    private static func applyStructuredPreset(
        _ preset: LLMParameterStructuredPreset?,
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

    /// Removes and returns the caller-supplied JSON schema payload required by structured output.
    private static func jsonSchemaPayload(from providerExtras: inout [String: JSONValue]) throws -> [String: JSONValue] {
        guard let value = providerExtras.removeValue(forKey: "json_schema"),
              let object = value.objectValue else {
            throw LLMProviderError.unsupportedParameter("response_format json_schema requires providerExtras.json_schema object.")
        }
        return object
    }

    /// Encodes provider-neutral tools for Chat Completions.
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

    /// Encodes one provider-neutral message for Chat Completions content.
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

    /// Encodes one provider-neutral message for Responses input content.
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

    /// Encodes provider-neutral tools for Responses function tools.
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

    /// Extracts token counters from provider usage metadata.
    static func usage(from object: [String: JSONValue], inputKey: String, outputKey: String) -> LLMUsage {
        LLMUsage(
            inputTokens: object.int(inputKey),
            outputTokens: object.int(outputKey),
            totalTokens: object.int("total_tokens")
        )
    }

    /// Returns a remote image URL or data URL for image content.
    private static func imageURL(from part: LLMContentPart) -> String? {
        if let sourceURL = part.sourceURL, !sourceURL.isEmpty { return sourceURL }
        guard let data = part.dataBase64, !data.isEmpty else { return nil }
        return "data:\(part.mimeType ?? "image/png");base64,\(data)"
    }

    /// Returns a data URL for file content when inline bytes are available.
    private static func fileData(from part: LLMContentPart) -> String? {
        guard let data = part.dataBase64, !data.isEmpty else { return nil }
        if data.hasPrefix("data:") { return data }
        return "data:\(part.mimeType ?? "application/octet-stream");base64,\(data)"
    }

    /// Returns true when content can be collapsed into a single provider text string.
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

    /// Derives a provider filename from the source URL when possible.
    private static func filename(from part: LLMContentPart) -> String {
        guard let sourceURL = part.sourceURL,
              let url = URL(string: sourceURL),
              !url.lastPathComponent.isEmpty else {
            return "input_file"
        }
        return url.lastPathComponent
    }
}
