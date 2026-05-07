import Foundation

/// Decodes provider model-list payloads into normalized model descriptors.
enum LLMModelMetadataDecoder {
    /// Maps OpenAI-compatible model objects using provider metadata plus bundled model defaults.
    static func openAICompatibleDescriptors(
        from data: [JSONValue],
        profile: LLMProviderProfile,
        endpointFamilies: [LLMEndpointFamily],
        defaultsCatalog: LLMDefaultsCatalog = .bundled
    ) -> [LLMModelDescriptor] {
        data.compactMap { item in
            guard let object = item.objectValue, let id = object.string("id") else { return nil }
            var descriptor = defaultsCatalog.modelDescriptor(
                providerID: profile.id,
                modelID: id,
                displayName: object.string("name") ?? object.string("display_name") ?? id,
                endpointFamilies: endpointFamilies,
                rawMetadataJSON: rawJSONString(from: item)
            )
            applyProviderMetadata(from: object, to: &descriptor)
            return descriptor
        }
    }

    /// Maps Anthropic model objects using provider metadata plus bundled model defaults.
    static func anthropicDescriptors(
        from data: [JSONValue],
        profile: LLMProviderProfile,
        defaultsCatalog: LLMDefaultsCatalog = .bundled
    ) -> [LLMModelDescriptor] {
        data.compactMap { item in
            guard let object = item.objectValue, let id = object.string("id") else { return nil }
            var descriptor = defaultsCatalog.modelDescriptor(
                providerID: profile.id,
                modelID: id,
                displayName: object.string("display_name") ?? object.string("name") ?? id,
                endpointFamilies: [.anthropicMessages],
                rawMetadataJSON: rawJSONString(from: item)
            )
            applyProviderMetadata(from: object, to: &descriptor)
            return descriptor
        }
    }

    /// Re-encodes raw provider metadata for diagnostics and persistence.
    static func rawJSONString(from value: JSONValue) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Reads known context-window fields from provider metadata.
    private static func contextWindow(from object: [String: JSONValue]) -> Int? {
        object.int("context_length")
            ?? object.int("context_window")
            ?? object.int("max_context_length")
            ?? object.int("max_context_window")
    }

    /// Applies direct provider metadata over already-resolved bundled defaults.
    private static func applyProviderMetadata(from object: [String: JSONValue], to descriptor: inout LLMModelDescriptor) {
        if let contextWindow = contextWindow(from: object) {
            descriptor.contextWindow = contextWindow
        }

        let directModalities = modalities(from: object)
        if !directModalities.isEmpty {
            descriptor.modalities = directModalities
        }

        let directParameters = supportedParameters(from: object)
        if !directParameters.isEmpty {
            descriptor.supportedParameters = directParameters
        }

        let directFeatures = schemaFeatures(from: object, parameters: directParameters)
        if !directFeatures.isEmpty {
            descriptor.schemaFeatures = directFeatures
        }
    }

    /// Reads provider-advertised parameter names.
    private static func supportedParameters(from object: [String: JSONValue]) -> [String] {
        let direct = stringArray(object["supported_parameters"])
            + stringArray(object["parameters"])
        return Array(Set(direct)).sorted()
    }

    /// Infers schema/runtime features from provider-advertised metadata.
    private static func schemaFeatures(
        from object: [String: JSONValue],
        parameters: [String]
    ) -> [LLMSchemaFeature] {
        var features = Set<LLMSchemaFeature>()
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

    /// Infers supported modalities from provider metadata.
    private static func modalities(from object: [String: JSONValue]) -> [LLMModality] {
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

        return Array(modalities).sorted { $0.rawValue < $1.rawValue }
    }

    /// Adds modalities detected in a provider text field.
    private static func appendModalities(from text: String?, to modalities: inout Set<LLMModality>) {
        guard let text else { return }
        let lowercased = text.lowercased()
        if lowercased.contains("text") { modalities.insert(.text) }
        if lowercased.contains("image") || lowercased.contains("vision") { modalities.insert(.image) }
        if lowercased.contains("audio") { modalities.insert(.audio) }
        if lowercased.contains("file") || lowercased.contains("document") { modalities.insert(.file) }
        if lowercased.contains("video") { modalities.insert(.video) }
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
