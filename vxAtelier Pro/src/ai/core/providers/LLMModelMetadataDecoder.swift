import Foundation

/// Decodes provider model-list payloads into normalized model descriptors.
enum LLMModelMetadataDecoder {
    /// Maps OpenAI-compatible model objects using the supplied profile defaults.
    static func openAICompatibleDescriptors(
        from data: [JSONValue],
        profile: LLMProviderProfile,
        endpointFamilies: [LLMEndpointFamily]
    ) -> [LLMModelDescriptor] {
        data.compactMap { item in
            guard let object = item.objectValue, let id = object.string("id") else { return nil }
            return LLMModelDescriptor(
                id: id,
                displayName: object.string("name") ?? object.string("display_name") ?? id,
                providerID: profile.id,
                contextWindow: contextWindow(from: object),
                endpointFamilies: endpointFamilies,
                modalities: modalities(from: object, fallback: profile.modalities),
                supportedParameters: supportedParameters(from: object, fallback: profile.supportedParameters),
                schemaFeatures: schemaFeatures(from: object, fallback: profile.schemaFeatures),
                rawMetadataJSON: rawJSONString(from: item)
            )
        }
    }

    /// Maps Anthropic model objects using Anthropic endpoint capabilities.
    static func anthropicDescriptors(
        from data: [JSONValue],
        profile: LLMProviderProfile
    ) -> [LLMModelDescriptor] {
        data.compactMap { item in
            guard let object = item.objectValue, let id = object.string("id") else { return nil }
            return LLMModelDescriptor(
                id: id,
                displayName: object.string("display_name") ?? object.string("name") ?? id,
                providerID: profile.id,
                contextWindow: contextWindow(from: object),
                endpointFamilies: [.anthropicMessages],
                modalities: modalities(from: object, fallback: profile.modalities),
                supportedParameters: supportedParameters(from: object, fallback: profile.supportedParameters),
                schemaFeatures: schemaFeatures(from: object, fallback: profile.schemaFeatures),
                rawMetadataJSON: rawJSONString(from: item)
            )
        }
    }

    /// Re-encodes raw provider metadata for diagnostics and persistence.
    static func rawJSONString(from value: JSONValue) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func contextWindow(from object: [String: JSONValue]) -> Int? {
        object.int("context_length")
            ?? object.int("context_window")
            ?? object.int("max_context_length")
            ?? object.int("max_context_window")
    }

    private static func supportedParameters(
        from object: [String: JSONValue],
        fallback: [String]
    ) -> [String] {
        let direct = stringArray(object["supported_parameters"])
            + stringArray(object["parameters"])
        return direct.isEmpty ? fallback : Array(Set(direct + fallback)).sorted()
    }

    private static func schemaFeatures(
        from object: [String: JSONValue],
        fallback: [LLMSchemaFeature]
    ) -> [LLMSchemaFeature] {
        let parameters = supportedParameters(from: object, fallback: [])
        var features = Set(fallback)
        if parameters.contains(where: { $0 == "tools" || $0 == "tool_choice" }) {
            features.insert(.tools)
        }
        if parameters.contains("response_format") {
            features.insert(.jsonObject)
        }
        if parameters.contains(where: { $0 == "json_schema" || $0 == "structured_outputs" }) {
            features.insert(.jsonSchema)
        }
        if parameters.contains(where: { $0 == "reasoning" || $0 == "thinking" }) {
            features.insert(.reasoning)
        }
        if object.bool("supports_streaming") == true || object.bool("streaming") == true {
            features.insert(.streaming)
        }
        return Array(features).sorted { $0.rawValue < $1.rawValue }
    }

    private static func modalities(
        from object: [String: JSONValue],
        fallback: [LLMModality]
    ) -> [LLMModality] {
        var modalities = Set<LLMModality>()
        appendModalities(from: object.string("modality"), to: &modalities)
        appendModalities(from: object.string("modalities"), to: &modalities)
        for value in stringArray(object["modalities"]) {
            appendModalities(from: value, to: &modalities)
        }

        if let architecture = object.object("architecture") {
            appendModalities(from: architecture.string("modality"), to: &modalities)
            for key in ["input_modalities", "output_modalities"] {
                for value in stringArray(architecture[key]) {
                    appendModalities(from: value, to: &modalities)
                }
            }
        }

        return modalities.isEmpty
            ? fallback
            : Array(modalities).sorted { $0.rawValue < $1.rawValue }
    }

    private static func appendModalities(from text: String?, to modalities: inout Set<LLMModality>) {
        guard let text else { return }
        let lowercased = text.lowercased()
        if lowercased.contains("text") { modalities.insert(.text) }
        if lowercased.contains("image") || lowercased.contains("vision") { modalities.insert(.image) }
        if lowercased.contains("audio") { modalities.insert(.audio) }
        if lowercased.contains("file") || lowercased.contains("document") { modalities.insert(.file) }
        if lowercased.contains("video") { modalities.insert(.video) }
    }

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
