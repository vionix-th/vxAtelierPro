import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMStreamingFixtureTests: LLMTestCase {
    func testOpenAIChatStreamingFixture() async throws {
        try installFixtureHandler(name: "openai_chat_stream", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let adapter = OpenAIChatAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest.runtimeEquivalent(
            providerID: .openAIPlatform,
            endpointFamily: .chatCompletions,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )

        let events = try await collectEvents(adapter.stream(
            request,
            configuration: config.llmProviderConfiguration(profile: adapter.profile)
        ))
        XCTAssertTrue(events.contains(.textDelta("Hello")))
        XCTAssertTrue(events.contains(where: { event in
            if case .toolCallCompleted(let call) = event {
                return call.callID == "call_1" && call.name == "lookup" && call.argumentsJSON == "{\"q\":\"test\"}"
            }
            return false
        }))
        XCTAssertTrue(events.contains(.runCompleted(responseID: nil, modelID: nil)))
    }

    func testOpenAIResponsesStreamingFixture() async throws {
        try installFixtureHandler(name: "openai_responses_stream", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest.runtimeEquivalent(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )

        let events = try await collectEvents(adapter.stream(
            request,
            configuration: config.llmProviderConfiguration(profile: adapter.profile)
        ))
        XCTAssertTrue(events.contains(.runStarted(requestID: "resp_fixture")))
        XCTAssertTrue(events.contains(.textDelta("Hello")))
        XCTAssertTrue(events.contains(.usage(LLMUsage(inputTokens: 5, outputTokens: 7, totalTokens: 12))))
        XCTAssertTrue(events.contains(.runCompleted(responseID: "resp_fixture", modelID: "gpt-4.1-mini")))
        XCTAssertTrue(events.contains(where: { event in
            if case .toolCallCompleted(let call) = event {
                return call.id == "fc_1" && call.callID == "call_1" && call.argumentsJSON == "{\"q\":\"test\"}"
            }
            return false
        }))
    }

    func testResponsesStreamWithoutCompletionEventFails() async throws {
        try installFixtureHandler(name: "cancellation", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let adapter = OpenAIResponsesAdapter(profile: LLMProviderRegistry.shared.profile(for: .openAIPlatform))
        let request = LLMRequest(
            providerID: .openAIPlatform,
            endpointFamily: .responses,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let config = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://unit.test/v1",
            defaultModel: "gpt-test",
            providerID: .openAIPlatform
        )

        await assertThrowsAsyncError(try await collectEvents(adapter.stream(
            request,
            configuration: config.llmProviderConfiguration(profile: adapter.profile)
        ))) { error in
            XCTAssertEqual(error as? LLMProviderError, .decoding("Provider stream ended before completion event."))
        }
    }

    func testAnthropicStreamingFixture() async throws {
        try installFixtureHandler(name: "anthropic_messages_stream", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let adapter = AnthropicMessagesAdapter(profile: LLMProviderRegistry.shared.profile(for: .anthropic))
        let request = LLMRequest.runtimeEquivalent(
            providerID: .anthropic,
            endpointFamily: .anthropicMessages,
            modelID: "claude-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])],
            options: LLMGenerationOptions(streamMode: .enabled)
        )
        let config = APIConfigurationItem(
            name: "Anthropic",
            apiKey: "key",
            baseURL: "https://unit.test",
            defaultModel: "claude-test",
            providerID: .anthropic
        )

        let events = try await collectEvents(adapter.stream(
            request,
            configuration: config.llmProviderConfiguration(profile: adapter.profile)
        ))
        XCTAssertTrue(events.contains(.runStarted(requestID: "msg_fixture")))
        XCTAssertTrue(events.contains(.textDelta("Hello")))
        XCTAssertTrue(events.contains(.runCompleted(responseID: nil, modelID: nil)))
        XCTAssertTrue(events.contains(where: { event in
            if case .toolCallCompleted(let call) = event {
                return call.callID == "toolu_1" && call.name == "lookup" && call.argumentsJSON == "{\"q\":\"test\"}"
            }
            return false
        }))
    }

    func testOpenAICompatibleModelMetadataFixtures() throws {
        let openRouterData = try fixtureJSON(name: "openrouter_models").objectValue?.array("data") ?? []
        let openRouterProfile = LLMProviderRegistry.shared.profile(for: .openRouter)
        let openRouterModels = LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: openRouterData,
            profile: openRouterProfile,
            endpointFamilies: [.chatCompletions]
        )
        XCTAssertEqual(openRouterModels.first?.id, "openai/gpt-4o-mini")
        XCTAssertEqual(openRouterModels.first?.displayName, "GPT-4o Mini")
        XCTAssertEqual(openRouterModels.first?.contextWindow, 128000)
        XCTAssertEqual(openRouterModels.first?.modalities, [.text])

        let lmStudioData = try fixtureJSON(name: "lmstudio_models").objectValue?.array("data") ?? []
        let lmStudioModels = LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: lmStudioData,
            profile: LLMProviderRegistry.shared.profile(for: .lmStudio),
            endpointFamilies: [.chatCompletions]
        )
        XCTAssertEqual(lmStudioModels.first?.id, "local-model")
        XCTAssertEqual(lmStudioModels.first?.modalities, [.text])

        let ollamaData = try fixtureJSON(name: "ollama_models").objectValue?.array("data") ?? []
        let ollamaModels = LLMModelMetadataDecoder.openAICompatibleDescriptors(
            from: ollamaData,
            profile: LLMProviderRegistry.shared.profile(for: .ollama),
            endpointFamilies: [.chatCompletions]
        )
        XCTAssertEqual(ollamaModels.first?.id, "llama3.2")
        XCTAssertEqual(ollamaModels.first?.endpointFamilies, [.chatCompletions])
    }

    func testMessageExportRoundtripPreservesPartsAndToolCalls() {
        let message = MessageItem(
            role: "assistant",
            contentParts: [
                MessageContentPartItem(index: 0, kind: .text, text: "Use tool")
            ]
        )
        message.toolCallItems = [
            ToolCallItem(callID: "call_1", providerCallID: "call_1", index: 0, name: "lookup", argumentsJSON: "{\"q\":\"test\"}")
        ]

        let exported = MessageExportData(message)
        let restored = exported.toDataItem()

        XCTAssertEqual(restored.displayText, "Use tool")
        XCTAssertEqual(restored.toolCallItems.count, 1)
        XCTAssertEqual(restored.toolCallItems.first?.argumentsJSON, "{\"q\":\"test\"}")
    }

    func testFixtureResourcesExist() throws {
        let names = [
            "openai_chat_stream",
            "openai_responses_stream",
            "anthropic_messages_stream",
            "openrouter_models",
            "lmstudio_models",
            "ollama_models",
            "malformed_stream",
            "retryable_failure",
            "cancellation"
        ]

        for name in names {
            let ext = name.contains("models") || name == "retryable_failure" ? "json" : "sse"
            XCTAssertNotNil(fixtureURL(name: name, fileExtension: ext), "Missing fixture \(name).\(ext)")
        }
    }
}
