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
        var options = LLMGenerationOptions(streamMode: .enabled)
        options.modelID = "gpt-4.1-mini"
        let request = LLMGenerationRequest.runtimeEquivalent(
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
            resolvedRoute: LLMResolvedProviderRoute(
                providerID: .openAIPlatform,
                adapterID: .openAIResponses,
                configuration: providerConfiguration
            ),
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

    func testProviderRunExecutorRejectsRouteAdapterMismatch() async throws {
        let environment = TestEnvironment()
        let conversation = environment.createConversation()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])]
        )
        let route = LLMResolvedProviderRoute(
            providerID: .openAIPlatform,
            adapterID: .openAIChatCompletions,
            configuration: LLMProviderConfiguration(
                providerID: .openAIPlatform,
                baseURL: "https://unit.test/v1"
            )
        )

        do {
            _ = try await ProviderRunExecutor().performRun(
                request: request,
                resolvedRoute: route,
                draftSink: RecordingDraftSink(),
                conversationID: conversation.id,
                retryPolicy: .disabled
            )
            XCTFail("Expected the executor to reject a route/adapter mismatch.")
        } catch let error as LLMProviderError {
            guard case .invalidConfiguration(let message) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error).")
            }
            XCTAssertTrue(message.contains("does not match request adapter"))
        }
    }

    func testProviderRunExecutorRejectsRouteTransportProviderMismatch() async throws {
        let environment = TestEnvironment()
        let conversation = environment.createConversation()
        let request = LLMGenerationRequest(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            messages: [LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])]
        )
        let route = LLMResolvedProviderRoute(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            configuration: LLMProviderConfiguration(
                providerID: .custom,
                baseURL: "https://unit.test/v1"
            )
        )

        do {
            _ = try await ProviderRunExecutor().performRun(
                request: request,
                resolvedRoute: route,
                draftSink: RecordingDraftSink(),
                conversationID: conversation.id,
                retryPolicy: .disabled
            )
            XCTFail("Expected the executor to reject a route/transport provider mismatch.")
        } catch let error as LLMProviderError {
            guard case .invalidConfiguration(let message) = error else {
                return XCTFail("Expected invalidConfiguration, got \(error).")
            }
            XCTAssertTrue(message.contains("does not match route provider"))
        }
    }
}

@MainActor
final class ConversationDraftStoreTests: LLMTestCase {
    func testToolCallUpdatesReplaceSnapshotsWithoutDuplicatingArguments() {
        let env = TestEnvironment()
        let conversation = env.createConversation()
        let store = ConversationDraftStore()
        store.start(conversationID: conversation.id)

        store.updateToolCalls([
            LLMToolCall(
                id: "fc_1",
                callID: "call_1",
                index: 0,
                name: "lookup",
                argumentsJSON: "{\"q\""
            )
        ], conversationID: conversation.id)
        store.updateToolCalls([
            LLMToolCall(
                id: "fc_1",
                callID: "call_1",
                index: 0,
                name: "lookup",
                argumentsJSON: "{\"q\":\"test\"}"
            )
        ], conversationID: conversation.id)

        let draft = store.draft(for: conversation.id)
        XCTAssertEqual(draft.toolCalls.count, 1)
        XCTAssertEqual(draft.toolCalls.first?.argumentsJSON, "{\"q\":\"test\"}")
        XCTAssertEqual(draft.toolCalls.first?.name, "lookup")
        XCTAssertEqual(draft.runStatus, .awaitingTools)
    }
}

@MainActor
final class ConversationPresentationTests: LLMTestCase {
    func testPresentationMatchesToolResultByProviderCallID() {
        let environment = TestEnvironment()
        let conversation = environment.createConversation()
        let turn = ConversationTurn(
            sequenceNumber: 0,
            userMessage: MessageItem(role: "user", text: "Look this up"),
            conversation: conversation
        )
        let call = ToolCallItem(
            callID: "fc_1",
            providerCallID: "call_1",
            index: 0,
            name: "lookup",
            argumentsJSON: "{\"q\":\"test\"}"
        )
        let assistantMessage = MessageItem(
            role: "assistant",
            text: "",
            toolCalls: [call]
        )
        let assistantEvent = TurnEvent(
            type: .assistant,
            message: assistantMessage,
            turn: turn
        )
        let resultMessage = MessageItem(
            role: "tool",
            contentParts: [MessageContentPartItem(index: 0, kind: .toolResult, text: "result")],
            toolCallId: "call_1"
        )
        let resultEvent = TurnEvent(
            type: .toolResult,
            message: resultMessage,
            turn: turn
        )
        turn.events = [assistantEvent, resultEvent]
        conversation.turns = [turn]

        let assistantRow = ConversationPresentationBuilder.build(conversation: conversation)
            .rows
            .first { $0.role == .assistant }

        XCTAssertEqual(assistantRow?.toolCalls.count, 1)
        XCTAssertEqual(assistantRow?.toolCalls.first?.name, "lookup")
        XCTAssertEqual(assistantRow?.toolResults.count, 1)
        XCTAssertEqual(assistantRow?.toolResults.first?.toolName, "lookup")
        XCTAssertEqual(assistantRow?.toolResults.first?.text, "result")
        XCTAssertEqual(assistantRow?.pendingToolResultCount, 0)
    }
}
