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
final class ConversationDisplayPolicyTests: LLMTestCase {
    func testToolResultResolverMatchesProviderCallID() {
        let call = ToolCallItem(
            callID: "fc_1",
            providerCallID: "call_1",
            index: 0,
            name: "lookup",
            argumentsJSON: "{\"q\":\"test\"}"
        )
        let resultMessage = MessageItem(
            role: "tool",
            contentParts: [MessageContentPartItem(index: 0, kind: .toolResult, text: "result")],
            toolCallId: "call_1"
        )
        let event = TurnEvent(type: .toolResult, message: resultMessage, turn: nil)

        let state = ToolResultDisplayResolver.resolve(calls: [call], events: [event])

        XCTAssertEqual(state.totalResults, 1)
        XCTAssertEqual(state.pendingCount, 0)
        XCTAssertEqual(state.results.first?.toolCall.name, "lookup")
        XCTAssertEqual(state.results.first?.event.message.displayText, "result")
    }

    func testActiveFollowUpDraftRendersAfterAssistantEventExists() {
        let draft = ConversationDraft(isActive: true, runStatus: .streaming)

        XCTAssertTrue(ConversationDraftRenderPolicy.shouldRender(
            isLastTurn: true,
            draft: draft,
            latestRunStatus: .streaming
        ))
    }

    func testCompletedDraftDoesNotRenderAfterPersistence() {
        let draft = ConversationDraft(isActive: false, runStatus: .completed)

        XCTAssertFalse(ConversationDraftRenderPolicy.shouldRender(
            isLastTurn: true,
            draft: draft,
            latestRunStatus: .completed
        ))
    }

    func testFailedDraftRendersErrorState() {
        let draft = ConversationDraft(isActive: false, runStatus: .failed, errorMessage: "boom")

        XCTAssertTrue(ConversationDraftRenderPolicy.shouldRender(
            isLastTurn: true,
            draft: draft,
            latestRunStatus: .failed
        ))
    }
}
