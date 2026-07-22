import Foundation

/// Decodes model-list payloads into provider metadata without catalog enrichment.
enum LLMModelMetadataDecoder {
    /// Maps OpenAI-compatible model objects into provider metadata.
    static func openAICompatibleMetadata(
        from data: [JSONValue],
        profile: LLMProviderProfile
    ) -> [LLMProviderModelMetadata] {
        data.compactMap { item in
            guard let object = item.objectValue, let id = object.string("id") else { return nil }
            return LLMProviderModelMetadata(
                id: id,
                displayName: object.string("name") ?? object.string("display_name"),
                providerID: profile.id,
                contextSize: contextSize(from: object),
                capabilityClaims: explicitCapabilityClaims(from: object),
                parameterSupportClaims: explicitParameterClaims(from: object),
                rawMetadataJSON: rawJSONString(from: item)
            )
        }
    }

    /// Maps Anthropic model objects into provider metadata.
    static func anthropicMetadata(
        from data: [JSONValue],
        profile: LLMProviderProfile
    ) -> [LLMProviderModelMetadata] {
        data.compactMap { item in
            guard let object = item.objectValue, let id = object.string("id") else { return nil }
            return LLMProviderModelMetadata(
                id: id,
                displayName: object.string("display_name") ?? object.string("name"),
                providerID: profile.id,
                contextSize: contextSize(from: object),
                capabilityClaims: explicitCapabilityClaims(from: object),
                parameterSupportClaims: explicitParameterClaims(from: object),
                rawMetadataJSON: rawJSONString(from: item)
            )
        }
    }

    /// Re-encodes raw provider metadata for diagnostics and persistence.
    static func rawJSONString(from value: JSONValue) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Reads known context-window fields from provider metadata.
    private static func contextSize(from object: [String: JSONValue]) -> Int? {
        object.int("context_length")
            ?? object.int("context_window")
            ?? object.int("max_context_length")
            ?? object.int("max_context_window")
    }

    /// Reads explicit provider claims without treating omitted capabilities as unsupported.
    private static func explicitCapabilityClaims(from object: [String: JSONValue]) -> [LLMCapabilityClaim] {
        var claims: [LLMModelCapability: LLMSupportState] = [:]
        for key in ["capabilities", "schema_features", "features"] {
            for value in stringArray(object[key]) {
                if let capability = LLMModelCapability(rawValue: value) {
                    claims[capability] = .supported
                }
            }
        }
        appendContentCapabilities(from: object, to: &claims)
        let booleanClaims: [LLMModelCapability: [String]] = [
            .text: ["supports_text"],
            .image: ["supports_image", "supports_images", "supports_vision"],
            .audio: ["supports_audio"],
            .file: ["supports_file", "supports_files"],
            .video: ["supports_video"],
            .tools: ["supports_tools", "supports_tool_calls"],
            .strictTools: ["supports_strict_tools"],
            .jsonSchema: ["supports_json_schema", "supports_structured_outputs"],
            .jsonObject: ["supports_json_object", "supports_json_mode"],
            .reasoning: ["supports_reasoning"],
            .usage: ["supports_usage"],
            .streaming: ["supports_streaming", "streaming"]
        ]
        for (capability, keys) in booleanClaims {
            for key in keys {
                if let value = object[key]?.boolValue {
                    claims[capability] = value ? .supported : .unsupported
                }
            }
        }
        return claims
            .map { LLMCapabilityClaim(capability: $0.key, state: $0.value) }
            .sorted { $0.capability.rawValue < $1.capability.rawValue }
    }

    /// Reads explicit content capability arrays from provider metadata.
    private static func appendContentCapabilities(
        from object: [String: JSONValue],
        to claims: inout [LLMModelCapability: LLMSupportState]
    ) {
        for value in stringArray(object["modalities"]) {
            appendCapability(value, to: &claims)
        }

        if let architecture = object.object("architecture") {
            for key in ["input_modalities", "output_modalities"] {
                for value in stringArray(architecture[key]) {
                    appendCapability(value, to: &claims)
                }
            }
        }
    }

    /// Reads non-exhaustive provider parameter claims without deriving support from omission.
    private static func explicitParameterClaims(from object: [String: JSONValue]) -> [LLMParameterSupportClaim] {
        var claims: [LLMParameterID: LLMSupportState] = [:]
        for value in stringArray(object["supported_parameters"]) {
            if let parameterID = semanticParameterID(forProviderToken: value) {
                claims[parameterID] = .supported
            }
        }

        for parameterID in LLMParameterID.allCases where parameterID.isProviderMappable {
            let key = "supports_\(parameterID.rawValue)"
            if let value = object[key]?.boolValue {
                claims[parameterID] = value ? .supported : .unsupported
            }
        }
        let booleanAliases: [LLMParameterID: [String]] = [
            .maxOutputTokens: ["supports_max_tokens", "supports_max_completion_tokens"],
            .stopSequences: ["supports_stop"],
            .responseFormat: ["supports_structured_outputs", "supports_json_schema"],
            .reasoningEffort: ["supports_reasoning"]
        ]
        for (parameterID, keys) in booleanAliases {
            for key in keys {
                if let value = object[key]?.boolValue {
                    claims[parameterID] = value ? .supported : .unsupported
                }
            }
        }

        return claims
            .map { LLMParameterSupportClaim(parameterID: $0.key, state: $0.value) }
            .sorted { $0.parameterID.rawValue < $1.parameterID.rawValue }
    }

    private static func semanticParameterID(forProviderToken token: String) -> LLMParameterID? {
        switch token.lowercased() {
        case "max_tokens", "max_completion_tokens", "max_output_tokens":
            return .maxOutputTokens
        case "stop", "stop_sequences":
            return .stopSequences
        case "response_format", "structured_outputs":
            return .responseFormat
        case "reasoning", "reasoning_effort":
            return .reasoningEffort
        default:
            return LLMParameterID(rawValue: token.lowercased())
        }
    }

    /// Adds one exact capability token from provider metadata.
    private static func appendCapability(
        _ value: String,
        to claims: inout [LLMModelCapability: LLMSupportState]
    ) {
        if let capability = LLMModelCapability(rawValue: value.lowercased()) {
            claims[capability] = .supported
        }
    }

    /// Reads a provider metadata field that may be either one string or an array of strings.
    private static func stringArray(_ value: JSONValue?) -> [String] {
        guard let value else { return [] }
        switch value {
        case .string(let string):
            return [string]
        case .array(let array):
            return array.compactMap { element in
                guard case .string(let string) = element else { return nil }
                return string
            }
        default:
            return []
        }
    }
}
