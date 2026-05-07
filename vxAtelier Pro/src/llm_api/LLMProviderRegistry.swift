import Foundation

/// Registry of built-in provider profiles and their adapter implementations.
struct LLMProviderRegistry {
    static let shared = LLMProviderRegistry()

    let profiles: [LLMProviderID: LLMProviderProfile]

    /// Builds the built-in provider profiles used by configuration and adapter selection.
    init() {
        let allProfiles = [
            LLMProviderProfile(
                id: .openAIPlatform,
                name: "OpenAI",
                defaultBaseURL: AppDefaults.OpenAi.baseURL,
                authKind: .bearerToken,
                defaultEndpointFamily: .responses,
                supportedEndpointFamilies: [.responses, .chatCompletions, .models],
                defaultModelID: AppDefaults.OpenAi.model,
                endpointPaths: [.responses: "/responses", .chatCompletions: AppDefaults.OpenAi.chatCompletionsPath, .models: AppDefaults.OpenAi.modelsPath],
                supportedParameters: ["temperature", "top_p", "max_output_tokens", "max_tokens", "stop", "response_format", "reasoning", "service_tier"],
                schemaFeatures: [.tools, .strictTools, .jsonSchema, .jsonObject, .reasoning, .usage, .streaming],
                modalities: [.text, .image, .file],
                isEnabled: true
            ),
            LLMProviderProfile(
                id: .openAIChatGPTSubscription,
                name: "ChatGPT Subscription",
                defaultBaseURL: "http://127.0.0.1",
                authKind: .chatGPTOAuth,
                defaultEndpointFamily: .responses,
                supportedEndpointFamilies: [.responses],
                defaultModelID: nil,
                endpointPaths: [:],
                supportedParameters: [],
                schemaFeatures: [.tools, .reasoning, .streaming],
                modalities: [.text],
                isEnabled: false
            ),
            LLMProviderProfile(
                id: .anthropic,
                name: "Anthropic",
                defaultBaseURL: AppDefaults.Anthropic.baseURL,
                authKind: .xAPIKey,
                defaultEndpointFamily: .anthropicMessages,
                supportedEndpointFamilies: [.anthropicMessages, .models],
                defaultModelID: AppDefaults.Anthropic.model,
                endpointPaths: [.anthropicMessages: AppDefaults.Anthropic.messagesPath, .models: AppDefaults.Anthropic.modelsPath],
                supportedParameters: ["temperature", "top_p", "max_output_tokens", "stop", "thinking"],
                schemaFeatures: [.tools, .reasoning, .usage, .streaming],
                modalities: [.text, .image],
                isEnabled: true
            ),
            LLMProviderProfile.openAICompatible(
                id: .openRouter,
                name: "OpenRouter",
                baseURL: "https://openrouter.ai/api",
                defaultModelID: "openai/gpt-4o-mini",
                chatPath: "/v1/chat/completions",
                modelsPath: "/v1/models"
            ),
            LLMProviderProfile.openAICompatible(
                id: .lmStudio,
                name: "LM Studio",
                baseURL: "http://localhost:1234",
                defaultModelID: nil,
                chatPath: "/v1/chat/completions",
                modelsPath: "/v1/models"
            ),
            LLMProviderProfile.openAICompatible(
                id: .ollama,
                name: "Ollama",
                baseURL: "http://localhost:11434",
                defaultModelID: nil,
                chatPath: "/v1/chat/completions",
                modelsPath: "/v1/models"
            ),
            LLMProviderProfile.openAICompatible(
                id: .xAI,
                name: "xAI",
                baseURL: AppDefaults.XAI.baseURL,
                defaultModelID: AppDefaults.XAI.model,
                chatPath: AppDefaults.XAI.chatCompletionsPath,
                modelsPath: AppDefaults.XAI.modelsPath
            ),
            LLMProviderProfile.openAICompatible(
                id: .deepSeek,
                name: "DeepSeek",
                baseURL: AppDefaults.DeepSeek.baseURL,
                defaultModelID: AppDefaults.DeepSeek.model,
                chatPath: AppDefaults.DeepSeek.chatCompletionsPath,
                modelsPath: AppDefaults.DeepSeek.modelsPath
            ),
            LLMProviderProfile.openAICompatible(
                id: .customOpenAICompatible,
                name: "Custom OpenAI Compatible",
                baseURL: AppDefaults.OpenAi.baseURL,
                defaultModelID: nil,
                chatPath: AppDefaults.OpenAi.chatCompletionsPath,
                modelsPath: AppDefaults.OpenAi.modelsPath
            )
        ]
        self.profiles = Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0) })
    }

    /// Returns the profile for a provider, falling back to the custom compatible profile.
    func profile(for id: LLMProviderID) -> LLMProviderProfile {
        profiles[id] ?? profiles[.customOpenAICompatible]!
    }

    /// Creates an adapter appropriate for the provider profile.
    func adapter(for id: LLMProviderID) -> LLMProviderAdapter {
        let profile = profile(for: id)
        guard profile.isEnabled else {
            return DisabledLLMProviderAdapter(
                profile: profile,
                message: "ChatGPT subscription auth is disabled because no supported embedded OAuth, device-code, or Codex-token flow is configured."
            )
        }

        switch id {
        case .openAIPlatform:
            return OpenAIResponsesAdapter(profile: profile)
        case .anthropic:
            return AnthropicMessagesAdapter(profile: profile)
        case .openAIChatGPTSubscription:
            return DisabledLLMProviderAdapter(profile: profile, message: "ChatGPT subscription auth is unavailable.")
        case .openRouter, .lmStudio, .ollama, .xAI, .deepSeek, .customOpenAICompatible:
            return OpenAIChatAdapter(profile: profile)
        }
    }

    /// Infers a provider identifier from user- or import-supplied provider text.
    static func providerID(fromProviderName providerName: String) -> LLMProviderID {
        let probe = providerName.lowercased()
        if probe.contains("anthropic") || probe.contains("claude") { return .anthropic }
        if probe.contains("openrouter") { return .openRouter }
        if probe.contains("lm studio") { return .lmStudio }
        if probe.contains("ollama") { return .ollama }
        if probe.contains("xai") || probe.contains("x.ai") || probe.contains("grok") { return .xAI }
        if probe.contains("deepseek") { return .deepSeek }
        if probe.contains("chatgpt") { return .openAIChatGPTSubscription }
        if probe.contains("custom") { return .customOpenAICompatible }
        if probe.contains("openai") { return .openAIPlatform }
        return .customOpenAICompatible
    }
}

/// Factories for reusable provider profile shapes.
extension LLMProviderProfile {
    /// Builds a profile for providers that implement the OpenAI Chat Completions shape.
    static func openAICompatible(
        id: LLMProviderID,
        name: String,
        baseURL: String,
        defaultModelID: String?,
        chatPath: String,
        modelsPath: String
    ) -> LLMProviderProfile {
        LLMProviderProfile(
            id: id,
            name: name,
            defaultBaseURL: baseURL,
            authKind: id == .lmStudio || id == .ollama ? .none : .bearerToken,
            defaultEndpointFamily: .chatCompletions,
            supportedEndpointFamilies: [.chatCompletions, .models],
            defaultModelID: defaultModelID,
            endpointPaths: [.chatCompletions: chatPath, .models: modelsPath],
            supportedParameters: ["temperature", "top_p", "max_tokens", "stop", "response_format"],
            schemaFeatures: [.tools, .jsonObject, .usage, .streaming],
            modalities: [.text],
            isEnabled: true
        )
    }
}
