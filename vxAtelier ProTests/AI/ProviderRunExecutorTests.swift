import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ProviderRunExecutorTests: LLMTestCase {
    func testProviderRunExecutorPublishesDraftEventsThroughSink() async throws {
        try installFixtureHandler(name: "openai_responses_stream", fileExtension: "sse")
        defer {
            URLProtocol.unregisterClass(MockLLMURLProtocol.self)
            MockLLMURLProtocol.requestHandler = nil
        }

        let env = TestEnvironment()
        let conversation = env.createConversation()
        let profile = LLMProviderRegistry.shared.profile(for: .openAIPlatform)
        var options = LLMGenerationOptions(streamMode: .enabled)
        options.modelID = "gpt-4.1-mini"
        options.adapterID = .openAIResponses
        let request = LLMRequest.runtimeEquivalent(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-4.1-mini",
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])
            ],
            options: options
        )
        let providerConfiguration = LLMProviderConfiguration(
            providerID: .openAIPlatform,
            authKind: .bearerToken,
            baseURL: "https://unit.test/v1",
            credential: .secret("key")
        )
        let sink = RecordingDraftSink()

        let result = try await ProviderRunExecutor().performRun(
            request: request,
            providerConfiguration: providerConfiguration,
            draftSink: sink,
            conversationID: conversation.id,
            retryPolicy: .disabled
        )

        XCTAssertEqual(result.text, "Hello")
        XCTAssertEqual(sink.text, "Hello")
        XCTAssertEqual(sink.toolCalls.first?.name, "lookup")
        XCTAssertEqual(result.toolCalls.first?.argumentsJSON, "{\"q\":\"test\"}")
        XCTAssertEqual(result.usage.totalTokens, 12)
    }
}
