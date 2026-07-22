import Foundation

/// OpenCode Zen adapter that routes each model through its advertised wire protocol.
struct OpenCodeZenAdapter: LLMProviderAdapter {
    private static let modelsPath = "/models"
    private static let modelsDevURL = "https://models.dev/api.json"

    let profile: LLMProviderProfile
    let adapterID: LLMAdapterID
    private let httpClient = LLMHTTPClient()

    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        delegate.generateEvents(
            request,
            configuration: transportConfiguration(configuration, for: adapterID),
            toolExecutor: toolExecutor
        )
    }

    func fetchModelMetadata(configuration: LLMProviderConfiguration) async throws -> [LLMModelMetadata] {
        var listingConfiguration = configuration
        listingConfiguration.authKind = .bearerToken
        let response: JSONValue = try await httpClient.getJSON(
            path: Self.modelsPath,
            configuration: httpClient.makeConfiguration(for: listingConfiguration),
            responseType: JSONValue.self
        )
        let availableModels = response.objectValue?.array("data") ?? []
        let enrichment = await modelsDevMetadata(configuration: configuration)

        return availableModels.compactMap { item in
            guard let id = item.objectValue?.string("id") else { return nil }
            return Self.candidate(modelID: id, metadata: enrichment[id])
        }
    }

    private var delegate: any LLMProviderAdapter {
        switch adapterID {
        case .openAIResponses:
            return OpenAIResponsesAdapter(profile: profile)
        case .anthropicMessages:
            return AnthropicMessagesAdapter(profile: profile)
        case .openAICompatibleChatCompletions:
            return OpenAICompatibleChatCompletionsAdapter(profile: profile)
        case .openAIChatCompletions, .foundationModels:
            return DisabledLLMProviderAdapter(
                profile: profile,
                message: "OpenCode Zen does not support \(adapterID.rawValue)."
            )
        }
    }

    private func transportConfiguration(
        _ configuration: LLMProviderConfiguration,
        for adapterID: LLMAdapterID
    ) -> LLMProviderConfiguration {
        var resolved = configuration
        resolved.authKind = Self.authKind(for: adapterID)
        return resolved
    }

    static func authKind(for adapterID: LLMAdapterID) -> LLMAuthKind {
        adapterID == .anthropicMessages ? .xAPIKey : .bearerToken
    }

    private func modelsDevMetadata(
        configuration: LLMProviderConfiguration
    ) async -> [String: [String: JSONValue]] {
        let publicConfiguration = LLMHTTPClient.Configuration(
            baseURL: "https://models.dev",
            headers: [:],
            requestTimeout: configuration.requestTimeout,
            streamIdleTimeout: configuration.streamIdleTimeout,
            maxResponseBodyBytes: configuration.maxResponseBodyBytes,
            maxSSEEventBytes: configuration.maxSSEEventBytes
        )
        do {
            let response: JSONValue = try await httpClient.getJSON(
                path: Self.modelsDevURL,
                configuration: publicConfiguration,
                responseType: JSONValue.self
            )
            let models = response.objectValue?
                .object("opencode")?
                .object("models") ?? [:]
            return models.reduce(into: [:]) { result, entry in
                if let object = entry.value.objectValue {
                    result[entry.key] = object
                }
            }
        } catch {
            await vxAtelierPro.log.warning(
                "OpenCode Zen model enrichment unavailable; using family routing: \(error.localizedDescription)"
            )
            return [:]
        }
    }

    static func adapterID(
        modelID: String,
        metadata: [String: JSONValue]?
    ) -> LLMAdapterID? {
        if let package = metadata?.object("provider")?.string("npm") {
            switch package {
            case "@ai-sdk/openai":
                return .openAIResponses
            case "@ai-sdk/anthropic":
                return .anthropicMessages
            case "@ai-sdk/openai-compatible":
                return .openAICompatibleChatCompletions
            case "@ai-sdk/google":
                return nil
            default:
                return nil
            }
        }

        let normalizedID = modelID.lowercased()
        if normalizedID.hasPrefix("gemini-") { return nil }
        if normalizedID.hasPrefix("gpt-") { return .openAIResponses }
        if normalizedID.hasPrefix("claude-") || normalizedID.hasPrefix("qwen") {
            return .anthropicMessages
        }
        return .openAICompatibleChatCompletions
    }

    static func candidate(
        modelID: String,
        metadata: [String: JSONValue]?
    ) -> LLMModelMetadata? {
        guard let routedAdapterID = adapterID(modelID: modelID, metadata: metadata) else {
            return nil
        }
        var candidate = LLMDefaultsCatalog.bundled.modelMetadata(
            providerID: .openCodeZen,
            modelID: modelID,
            displayName: metadata?.string("name") ?? modelID,
            rawMetadataJSON: metadata
                .map { JSONValue.object($0) }
                .flatMap(LLMModelMetadataDecoder.rawJSONString)
        )
        candidate.adapterID = routedAdapterID
        if let contextSize = metadata?.object("limit")?.int("context") {
            candidate.contextSize = contextSize
        }
        if let metadata {
            candidate.capabilities = capabilities(from: metadata)
        }
        return candidate
    }

    static func capabilities(from metadata: [String: JSONValue]) -> [LLMModelCapability] {
        var capabilities: Set<LLMModelCapability> = [.text, .usage, .streaming]
        if metadata.bool("tool_call") == true {
            capabilities.insert(.tools)
        }
        if metadata.bool("structured_output") == true {
            capabilities.insert(.jsonSchema)
            capabilities.insert(.jsonObject)
        }
        if metadata.bool("reasoning") == true {
            capabilities.insert(.reasoning)
        }
        for modality in metadata.object("modalities")?.array("input") ?? [] {
            switch modality.stringValue?.lowercased() {
            case "image": capabilities.insert(.image)
            case "audio": capabilities.insert(.audio)
            case "video": capabilities.insert(.video)
            case "pdf", "file": capabilities.insert(.file)
            default: break
            }
        }
        return capabilities.sorted { $0.rawValue < $1.rawValue }
    }
}
