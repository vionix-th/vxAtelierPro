import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationRunStoreTests: XCTestCase {
    func testRunStoreRollsBackTurnBeforeRunCreation() throws {
        let env = TestEnvironment()
        let conversation = env.createConversation()
        let store = ConversationRunStore()

        let turn = try store.startTurn(message: "Hello", in: conversation)

        XCTAssertEqual(conversation.turns.count, 1)
        XCTAssertEqual(turn.responseRuns.count, 0)

        try store.rollbackTurn(turn, from: conversation)

        XCTAssertTrue(conversation.turns.isEmpty)
    }

    func testRunStorePersistsProviderResultAndAssistantMessage() throws {
        let env = TestEnvironment()
        let conversation = env.createConversation()
        let store = ConversationRunStore()
        let turn = try store.startTurn(message: "Hello", in: conversation)
        let request = LLMRequest.runtimeEquivalent(
            providerID: .openAIPlatform,
            adapterID: .openAIResponses,
            modelID: "gpt-test",
            messages: [
                LLMMessage(role: "user", content: [LLMContentPart(kind: .text, text: "Hello")])
            ]
        )
        let run = try store.createResponseRun(for: request, turn: turn, conversation: conversation)
        let result = ProviderRunResult(
            text: "Done",
            usage: LLMUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3),
            metadata: LLMResponseMetadata(statusCode: 200, requestID: "req_store")
        )

        let message = try store.applyProviderResult(result, to: run, turn: turn, conversation: conversation)

        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.requestID, "req_store")
        XCTAssertEqual(run.totalTokens, 3)
        XCTAssertEqual(message?.displayText, "Done")
        XCTAssertEqual(turn.events.first?.type, .assistant)
    }
}
