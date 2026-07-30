import Foundation

/// Shared request encoders for OpenAI-shaped wire formats.
enum OpenAIEncoding {
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
        parameters: [LLMActiveParameter],
        reservedProviderExtraKeys: Set<String> = [],
        excludedStructuredPresets: Set<LLMParameterStructuredPreset> = []
    ) throws {
        var providerSpecificOptions = options.providerSpecificOptions
        let activeIDs = Set(parameters.map(\.parameterID))
        for parameterID in LLMParameterID.allCases where !activeIDs.contains(parameterID) {
            providerSpecificOptions.removeValue(forKey: parameterID.rawValue)
        }
        for parameter in parameters {
            let mapping = parameter.mapping
            guard mapping.encodingKind != .adapter else {
                providerSpecificOptions.removeValue(forKey: mapping.parameterID.rawValue)
                continue
            }
            guard let value = options.jsonValue(for: mapping.parameterID) else {
                throw LLMProviderError.requestEncoding(
                    "Active parameter \(mapping.parameterID.rawValue) has no value."
                )
            }
            providerSpecificOptions.removeValue(forKey: mapping.parameterID.rawValue)

            switch mapping.encodingKind {
            case .adapter:
                break
            case .key:
                guard !mapping.wireKey.isEmpty else {
                    throw LLMProviderError.requestEncoding("\(mapping.parameterID.rawValue) has no wire key.")
                }
                guard body[mapping.wireKey] == nil else {
                    throw LLMProviderError.requestEncoding(
                        "\(mapping.parameterID.rawValue) maps to reserved or duplicate key \(mapping.wireKey)."
                    )
                }
                body[mapping.wireKey] = value
            case .preset:
                if let preset = mapping.structuredPreset,
                   excludedStructuredPresets.contains(preset) {
                    continue
                }
                try applyStructuredPreset(mapping.structuredPreset, value: value, providerSpecificOptions: &providerSpecificOptions, to: &body)
            }
        }

        for (key, value) in providerSpecificOptions {
            guard !reservedProviderExtraKeys.contains(key), body[key] == nil else {
                throw LLMProviderError.requestEncoding("providerSpecificOptions.\(key) cannot override a reserved request field.")
            }
            body[key] = value
        }
    }

    /// Encodes provider-specific structured parameters that need nested request bodies.
    private static func applyStructuredPreset(
        _ preset: LLMParameterStructuredPreset?,
        value: JSONValue,
        providerSpecificOptions: inout [String: JSONValue],
        to body: inout [String: JSONValue]
    ) throws {
        guard let preset else {
            throw LLMProviderError.requestEncoding("Structured parameter mapping requires a preset.")
        }
        switch preset {
        case .openAIChatResponseFormat:
            switch value.stringValue {
            case "json_object", "jsonObject":
                try setUnique(
                    .object(["type": .string("json_object")]),
                    for: "response_format",
                    in: &body
                )
            case "json_schema", "jsonSchema":
                try setUnique(
                    .object([
                        "type": .string("json_schema"),
                        "json_schema": .object(try jsonSchemaPayload(from: &providerSpecificOptions))
                    ]),
                    for: "response_format",
                    in: &body
                )
            default:
                break
            }
        case .openAIResponsesTextFormat:
            switch value.stringValue {
            case "json_object", "jsonObject":
                try merge(
                    ["format": .object(["type": .string("json_object")])],
                    into: "text",
                    in: &body
                )
            case "json_schema", "jsonSchema":
                var format = try jsonSchemaPayload(from: &providerSpecificOptions)
                format["type"] = .string("json_schema")
                try merge(["format": .object(format)], into: "text", in: &body)
            default:
                break
            }
        case .openAIResponsesReasoning:
            if let effort = value.stringValue, !effort.isEmpty {
                try merge(["effort": .string(effort)], into: "reasoning", in: &body)
            }
        case .openAIResponsesTextVerbosity:
            if let verbosity = value.stringValue, !verbosity.isEmpty {
                try merge(["verbosity": .string(verbosity)], into: "text", in: &body)
            }
        case .openAIResponsesReasoningSummary:
            if let summary = value.stringValue, !summary.isEmpty {
                try merge(["summary": .string(summary)], into: "reasoning", in: &body)
            }
        case .openRouterReasoning:
            throw LLMProviderError.requestEncoding(
                "OpenRouter reasoning must be encoded by OpenRouterChatCompletionsAdapter."
            )
        case .anthropicThinking:
            throw LLMProviderError.requestEncoding(
                "Anthropic thinking is not representable by an OpenAI wire encoder."
            )
        }
    }

    private static func setUnique(
        _ value: JSONValue,
        for key: String,
        in body: inout [String: JSONValue]
    ) throws {
        guard body[key] == nil else {
            throw LLMProviderError.requestEncoding("Structured parameter mapping collides with request field \(key).")
        }
        body[key] = value
    }

    private static func merge(
        _ values: [String: JSONValue],
        into key: String,
        in body: inout [String: JSONValue]
    ) throws {
        var object: [String: JSONValue]
        if let existing = body[key] {
            guard let existingObject = existing.objectValue else {
                throw LLMProviderError.requestEncoding(
                    "Structured parameter mapping collides with request field \(key)."
                )
            }
            object = existingObject
        } else {
            object = [:]
        }
        for (nestedKey, value) in values {
            guard object[nestedKey] == nil else {
                throw LLMProviderError.requestEncoding(
                    "Structured parameter mapping collides with request field \(key).\(nestedKey)."
                )
            }
            object[nestedKey] = value
        }
        body[key] = .object(object)
    }

    /// Removes and returns the caller-supplied JSON schema payload required by structured output.
    private static func jsonSchemaPayload(from providerSpecificOptions: inout [String: JSONValue]) throws -> [String: JSONValue] {
        guard let value = providerSpecificOptions.removeValue(forKey: "json_schema"),
              let object = value.objectValue else {
            throw LLMProviderError.requestEncoding("response_format json_schema requires providerSpecificOptions.json_schema object.")
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
            return .string(message.textContent)
        }

        return .array(try parts.map { part in
            switch part.kind {
            case .text, .reasoning, .toolResult:
                return .object(["type": .string("text"), "text": .string(part.text ?? "")])
            case .image:
                guard let url = imageURL(from: part) else {
                    throw LLMProviderError.requestEncoding("OpenAI Chat image content requires sourceURL or dataBase64.")
                }
                return .object([
                    "type": .string("image_url"),
                    "image_url": .object(["url": .string(url)])
                ])
            case .file:
                guard let data = fileData(from: part) else {
                    throw LLMProviderError.requestEncoding("OpenAI Chat file content requires dataBase64.")
                }
                return .object([
                    "type": .string("file"),
                    "file": .object([
                        "filename": .string(filename(from: part)),
                        "file_data": .string(data)
                    ])
                ])
            case .audio:
                throw LLMProviderError.requestEncoding("OpenAI Chat audio content is not encodable by this adapter.")
            }
        })
    }

    /// Encodes one provider-neutral message for Responses input content.
    static func responsesContent(from message: LLMMessage) throws -> JSONValue {
        let parts = message.content
        if isPlainText(parts) {
            return .string(message.textContent)
        }

        return .array(try parts.map { part in
            switch part.kind {
            case .text, .reasoning, .toolResult:
                return .object(["type": .string("input_text"), "text": .string(part.text ?? "")])
            case .image:
                guard let url = imageURL(from: part) else {
                    throw LLMProviderError.requestEncoding("OpenAI Responses image content requires sourceURL or dataBase64.")
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
                    throw LLMProviderError.requestEncoding("OpenAI Responses file content requires sourceURL or dataBase64.")
                }
                return .object(file)
            case .audio:
                throw LLMProviderError.requestEncoding("OpenAI Responses audio content is not encodable by this adapter.")
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
