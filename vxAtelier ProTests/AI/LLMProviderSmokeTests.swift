import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMProviderSmokeTests: XCTestCase {
    func testOpenAIResponsesAndChatStreamingModes() async throws {
        try requireSmokeEnabled()
        let apiKey = try requireEnvironment("VX_OPENAI_API_KEY")
        let model = environment["VX_OPENAI_MODEL"] ?? AppDefaults.OpenAi.model
        let config = APIConfigurationItem(
            name: "OpenAI Smoke",
            apiKey: apiKey,
            baseURL: AppDefaults.OpenAi.baseURL,
            defaultModel: model,
            providerID: .openAIPlatform
        )
        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))

        try await assertProviderResponds(
            adapter: adapter,
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            model: model,
            config: config,
            streamMode: .disabled
        )
        try await assertProviderResponds(
            adapter: adapter,
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            model: model,
            config: config,
            streamMode: .enabled
        )
        try await assertProviderResponds(
            adapter: adapter,
            providerID: .openAIPlatform,
            endpointFamily: .chatCompletions,
            model: model,
            config: config,
            streamMode: .disabled
        )
        try await assertProviderResponds(
            adapter: adapter,
            providerID: .openAIPlatform,
            endpointFamily: .chatCompletions,
            model: model,
            config: config,
            streamMode: .enabled
        )
    }

    func testAnthropicStreamingModes() async throws {
        try requireSmokeEnabled()
        let apiKey = try requireEnvironment("VX_ANTHROPIC_API_KEY")
        let model = environment["VX_ANTHROPIC_MODEL"] ?? AppDefaults.Anthropic.model
        let config = APIConfigurationItem(
            name: "Anthropic Smoke",
            apiKey: apiKey,
            baseURL: AppDefaults.Anthropic.baseURL,
            defaultModel: model,
            providerID: .anthropic
        )
        let adapter = AnthropicMessagesAdapter(profile: LLMProviderRegistry.shared.profile(for: .anthropic))

        try await assertProviderResponds(
            adapter: adapter,
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            model: model,
            config: config,
            streamMode: .disabled
        )
        try await assertProviderResponds(
            adapter: adapter,
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            model: model,
            config: config,
            streamMode: .enabled
        )
    }

    func testOpenRouterStreamingModes() async throws {
        try requireSmokeEnabled()
        let apiKey = try requireEnvironment("VX_OPENROUTER_API_KEY")
        let profile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let model = environment["VX_OPENROUTER_MODEL"] ?? profile.defaultModelID ?? "openai/gpt-4o-mini"
        let config = APIConfigurationItem(
            name: "OpenRouter Smoke",
            apiKey: apiKey,
            baseURL: profile.defaultBaseURL,
            defaultModel: model,
            providerID: .openRouter
        )
        let adapter = OpenAIChatAdapter(profile: profile)

        try await assertProviderResponds(
            adapter: adapter,
            providerID: .openRouter,
            endpointFamily: .chatCompletions,
            model: model,
            config: config,
            streamMode: .disabled
        )
        try await assertProviderResponds(
            adapter: adapter,
            providerID: .openRouter,
            endpointFamily: .chatCompletions,
            model: model,
            config: config,
            streamMode: .enabled
        )
    }

    func testLMStudioStreamingModes() async throws {
        try requireSmokeEnabled()
        let baseURL = try requireEnvironment("VX_LMSTUDIO_BASE_URL")
        let model = try requireEnvironment("VX_LMSTUDIO_MODEL")
        let profile = LLMProviderRegistry.shared.profile(for: .lmStudio)
        let config = APIConfigurationItem(
            name: "LM Studio Smoke",
            apiKey: "",
            baseURL: baseURL,
            defaultModel: model,
            providerID: .lmStudio
        )
        let adapter = OpenAIChatAdapter(profile: profile)

        try await assertProviderResponds(
            adapter: adapter,
            providerID: .lmStudio,
            endpointFamily: .chatCompletions,
            model: model,
            config: config,
            streamMode: .disabled
        )
        try await assertProviderResponds(
            adapter: adapter,
            providerID: .lmStudio,
            endpointFamily: .chatCompletions,
            model: model,
            config: config,
            streamMode: .enabled
        )
    }

    func testOllamaStreamingModes() async throws {
        try requireSmokeEnabled()
        let baseURL = try requireEnvironment("VX_OLLAMA_BASE_URL")
        let model = try requireEnvironment("VX_OLLAMA_MODEL")
        let profile = LLMProviderRegistry.shared.profile(for: .ollama)
        let config = APIConfigurationItem(
            name: "Ollama Smoke",
            apiKey: "",
            baseURL: baseURL,
            defaultModel: model,
            providerID: .ollama
        )
        let adapter = OpenAIChatAdapter(profile: profile)

        try await assertProviderResponds(
            adapter: adapter,
            providerID: .ollama,
            endpointFamily: .chatCompletions,
            model: model,
            config: config,
            streamMode: .disabled
        )
        try await assertProviderResponds(
            adapter: adapter,
            providerID: .ollama,
            endpointFamily: .chatCompletions,
            model: model,
            config: config,
            streamMode: .enabled
        )
    }

    private var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    private func requireSmokeEnabled() throws {
        guard environment["VX_LLM_SMOKE_TESTS"] == "1" else {
            throw XCTSkip("Set VX_LLM_SMOKE_TESTS=1 and provider-specific environment variables to run live LLM smoke tests.")
        }
    }

    private func requireEnvironment(_ key: String) throws -> String {
        guard let value = environment[key], !value.isEmpty else {
            throw XCTSkip("Missing \(key).")
        }
        return value
    }

    private func assertProviderResponds(
        adapter: LLMProviderAdapter,
        providerID: LLMProviderID,
        endpointFamily: LLMEndpointFamily,
        model: String,
        config: APIConfigurationItem,
        streamMode: LLMGenerationOptions.StreamMode
    ) async throws {
        let request = LLMRequest(
            providerID: providerID,
            endpointFamily: endpointFamily,
            modelID: model,
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Reply with only: ok")])
            ],
            options: LLMGenerationOptions(maxOutputTokens: 16, streamMode: streamMode)
        )
        let events = try await collectEvents(adapter.stream(request, configuration: config))
        XCTAssertTrue(events.contains(where: { event in
            if case .runCompleted = event { return true }
            return false
        }))
        XCTAssertTrue(events.contains(where: { event in
            if case .textDelta(let text) = event {
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }))
    }

    private func collectEvents(
        _ stream: AsyncThrowingStream<LLMStreamEvent, Error>
    ) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}
