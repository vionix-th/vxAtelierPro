import Foundation

/// Decodes provider model-list payloads into normalized draft model candidates.
enum LLMModelMetadataDecoder {
    /// Maps OpenAI-compatible model objects using provider metadata plus bundled model defaults.
    static func openAICompatibleCandidates(
        from data: [JSONValue],
        profile: LLMProviderProfile,
        defaultsCatalog: LLMDefaultsCatalog = .bundled
    ) -> [LLMModelDescriptor] {
        data.compactMap { item in
            guard let object = item.objectValue, let id = object.string("id") else { return nil }
            var candidate = defaultsCatalog.modelDescriptor(
                providerID: profile.id,
                modelID: id,
                displayName: object.string("name") ?? object.string("display_name") ?? id,
                rawMetadataJSON: rawJSONString(from: item)
            )
            applyProviderMetadata(from: object, to: &candidate)
            return candidate
        }
    }

    /// Maps Anthropic model objects using provider metadata plus bundled model defaults.
    static func anthropicCandidates(
        from data: [JSONValue],
        profile: LLMProviderProfile,
        defaultsCatalog: LLMDefaultsCatalog = .bundled
    ) -> [LLMModelDescriptor] {
        data.compactMap { item in
            guard let object = item.objectValue, let id = object.string("id") else { return nil }
            var candidate = defaultsCatalog.modelDescriptor(
                providerID: profile.id,
                modelID: id,
                displayName: object.string("display_name") ?? object.string("name") ?? id,
                rawMetadataJSON: rawJSONString(from: item)
            )
            applyProviderMetadata(from: object, to: &candidate)
            return candidate
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
    private static func applyProviderMetadata(from object: [String: JSONValue], to candidate: inout LLMModelDescriptor) {
        if let contextWindow = contextWindow(from: object) {
            candidate.contextWindow = contextWindow
        }

        let directCapabilities = explicitCapabilities(from: object)
        if !directCapabilities.isEmpty {
            candidate.capabilities = directCapabilities
        }
    }

    /// Reads explicit provider capability fields.
    private static func explicitCapabilities(from object: [String: JSONValue]) -> [LLMModelCapability] {
        var capabilities = Set<LLMModelCapability>()
        for key in ["capabilities", "schema_features", "features"] {
            for value in stringArray(object[key]) {
                if let capability = LLMModelCapability(rawValue: value) {
                    capabilities.insert(capability)
                }
            }
        }
        appendContentCapabilities(from: object, to: &capabilities)
        if object.bool("supports_streaming") == true || object.bool("streaming") == true {
            capabilities.insert(.streaming)
        }
        return Array(capabilities).sorted { $0.rawValue < $1.rawValue }
    }

    /// Reads explicit content capability arrays from provider metadata.
    private static func appendContentCapabilities(from object: [String: JSONValue], to capabilities: inout Set<LLMModelCapability>) {
        for value in stringArray(object["modalities"]) {
            appendCapability(value, to: &capabilities)
        }

        if let architecture = object.object("architecture") {
            for key in ["input_modalities", "output_modalities"] {
                for value in stringArray(architecture[key]) {
                    appendCapability(value, to: &capabilities)
                }
            }
        }
    }

    /// Adds one exact capability token from provider metadata.
    private static func appendCapability(_ value: String, to capabilities: inout Set<LLMModelCapability>) {
        if let capability = LLMModelCapability(rawValue: value.lowercased()) {
            capabilities.insert(capability)
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
