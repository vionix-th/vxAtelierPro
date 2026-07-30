import Foundation

/// OpenCode Zen transport wrapper for one configuration-selected wire protocol.
struct OpenCodeZenAdapter: LLMProviderAdapter {
    private static let modelsPath = "/models"
    private static let chatModelPrefixes = [
        "grok-",
        "deepseek-",
        "minimax-",
        "glm-",
        "kimi-",
        "mimo-",
        "laguna-",
        "ling-",
        "nemotron-",
        "north-"
    ]
    private static let chatModelIDs = ["big-pickle"]

    let profile: LLMProviderProfile
    let adapterID: LLMAdapterID
    private let httpClient = LLMHTTPClient()

    func generateEvents(
        _ request: LLMGenerationRequest,
        configuration: LLMProviderConfiguration,
        toolExecutor: LLMToolExecutionHandler?
    ) -> AsyncThrowingStream<LLMGenerationEvent, Error> {
        guard Self.supports(modelID: request.modelID, adapterID: adapterID) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMProviderError.invalidConfiguration(
                    "\(request.modelID) is not compatible with \(adapterID.displayName) on OpenCode Zen."
                ))
            }
        }

        return delegate.generateEvents(
            request,
            configuration: transportConfiguration(configuration),
            toolExecutor: toolExecutor
        )
    }

    func fetchModelMetadata(
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        var listingConfiguration = configuration
        listingConfiguration.authKind = .bearerToken
        let response: JSONValue = try await httpClient.getJSON(
            path: Self.modelsPath,
            configuration: httpClient.makeConfiguration(for: listingConfiguration),
            responseType: JSONValue.self
        )
        guard let data = response.objectValue?.array("data") else { return [] }

        return LLMModelMetadataDecoder.openAICompatibleMetadata(
            from: data,
            profile: profile
        ).filter {
            Self.supports(modelID: $0.id, adapterID: adapterID)
        }
    }

    static func supports(modelID: String, adapterID: LLMAdapterID) -> Bool {
        supportedAdapterID(for: modelID) == adapterID
    }

    static func supportedAdapterID(for modelID: String) -> LLMAdapterID? {
        let normalizedID = modelID.lowercased()
        if normalizedID.hasPrefix("gpt-") {
            return .openAIResponses
        }
        if normalizedID.hasPrefix("claude-") || normalizedID.hasPrefix("qwen") {
            return .anthropicMessages
        }
        if chatModelPrefixes.contains(where: { normalizedID.hasPrefix($0) })
            || chatModelIDs.contains(normalizedID) {
            return .openAICompatibleChatCompletions
        }
        return nil
    }

    static func authKind(for adapterID: LLMAdapterID) -> LLMAuthKind {
        adapterID == .anthropicMessages ? .xAPIKey : .bearerToken
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
                message: "OpenCode Zen does not support \(adapterID.displayName)."
            )
        }
    }

    private func transportConfiguration(
        _ configuration: LLMProviderConfiguration
    ) -> LLMProviderConfiguration {
        var resolved = configuration
        resolved.authKind = Self.authKind(for: adapterID)
        return resolved
    }
}
