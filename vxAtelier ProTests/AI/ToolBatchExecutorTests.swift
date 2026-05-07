import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ToolBatchExecutorTests: LLMTestCase {
    func testConfigurableToolDefaultsRoundTripThroughConversationOptions() throws {
        let options = ConversationOptions(shouldSetupParameters: false)
        let defaults = ListShortcutsTool().defaultConfiguration()

        options.setToolConfiguration("list_shortcuts", configuration: defaults)

        let restored = try XCTUnwrap(options.getToolConfiguration("list_shortcuts"))
        XCTAssertEqual(restored["Restricted"]?.boolValue, false)
        XCTAssertEqual(restored["RestrictedList"]?.objectValue?["ID0001"]?.stringValue, "Shortcut Name A")
    }

    func testNonConfigurableToolDoesNotExposeConfiguration() {
        XCTAssertNil(RunShortcutTool() as? any ConfigurableLLMTool)
    }

    func testSuccessfulToolExecutionUsesTypedCallAndEmptyDefaultConfiguration() async throws {
        let fixture = makeToolExecutionFixture(toolName: UnitEchoTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitEchoTool.toolName, enabled: true)

        try await executeWithStore(
            toolCall,
            conversation: conversation,
            turn: turn,
            toolCatalog: StaticLLMToolCatalog([UnitEchoTool()])
        )

        XCTAssertEqual(toolCall.status, .completed)
        XCTAssertEqual(toolCall.resultMessage?.displayText, "id=call_1 name=unit_echo_tool args={\"value\":\"ok\"} config=0 title=Tool Test turn=0")
        XCTAssertEqual(turn.events.first?.type, .toolResult)
    }

    func testListShortcutsToolReceivesJSONValueConfiguration() async throws {
        let env = TestEnvironment()
        let conversation = ConversationItem("Shortcuts", options: ConversationOptions(shouldSetupParameters: false))
        let turn = ConversationTurn(
            sequenceNumber: 0,
            userMessage: MessageItem(role: "user", text: "List shortcuts"),
            conversation: conversation
        )
        conversation.turns.append(turn)
        env.modelContext.insert(conversation)
        let call = LLMToolExecutionCall(
            id: "call_shortcuts",
            name: "list_shortcuts",
            argumentsJSON: "{}",
            configuration: [
                "Restricted": .boolean(true),
                "RestrictedList": .object([
                    "ID0001": .string("Shortcut Name A")
                ])
            ],
            context: LLMToolExecutionContext(conversation: conversation, turn: turn)
        )

        let result = try await ListShortcutsTool().execute(call)

        let data = try XCTUnwrap(result.data(using: .utf8))
        let shortcuts = try JSONDecoder().decode([[String: String]].self, from: data)
        XCTAssertEqual(shortcuts, [["id": "ID0001", "name": "Shortcut Name A"]])
    }

    func testDisabledToolCallFailsAndPersistsFailedStatus() async throws {
        let fixture = makeToolExecutionFixture(toolName: UnitEchoTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitEchoTool.toolName, enabled: false)

        await assertThrowsAsyncError(try await executeWithStore(
            toolCall,
            conversation: conversation,
            turn: turn,
            toolCatalog: StaticLLMToolCatalog([UnitEchoTool()])
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool '\(UnitEchoTool.toolName)' is not enabled."))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool '\(UnitEchoTool.toolName)' is not enabled.")
    }

    func testThrownToolErrorPersistsFailedStatus() async throws {
        let fixture = makeToolExecutionFixture(toolName: UnitFailingTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitFailingTool.toolName, enabled: true)

        await assertThrowsAsyncError(try await executeWithStore(
            toolCall,
            conversation: conversation,
            turn: turn,
            toolCatalog: StaticLLMToolCatalog([UnitFailingTool()])
        )) { error in
            XCTAssertEqual(error as? LLMToolExecutionError, .executionFailed("unit failure"))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "unit failure")
    }

    func testMissingToolCallFailsAndPersistsFailedStatus() async throws {
        let missingToolName = "unit_missing_tool"
        let fixture = makeToolExecutionFixture(toolName: missingToolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(missingToolName, enabled: true)

        await assertThrowsAsyncError(try await executeWithStore(
            toolCall,
            conversation: conversation,
            turn: turn,
            toolCatalog: StaticLLMToolCatalog([])
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool not found: \(missingToolName)"))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool not found: \(missingToolName)")
    }

    func testNonExecutableToolCallFailsAndPersistsFailedStatus() async throws {
        let fixture = makeToolExecutionFixture(toolName: UnitSchemaOnlyTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitSchemaOnlyTool.toolName, enabled: true)

        await assertThrowsAsyncError(try await executeWithStore(
            toolCall,
            conversation: conversation,
            turn: turn,
            toolCatalog: StaticLLMToolCatalog([UnitSchemaOnlyTool()])
        )) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool execution not supported: \(UnitSchemaOnlyTool.toolName)"))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool execution not supported: \(UnitSchemaOnlyTool.toolName)")
    }

    private func executeWithStore(
        _ toolCall: ToolCallItem,
        conversation: ConversationItem,
        turn: ConversationTurn,
        toolCatalog: LLMToolCatalog
    ) async throws {
        let store = ConversationRunStore()
        try store.markToolExecuting(toolCall, conversation: conversation)
        do {
            let output = try await ToolBatchExecutor(toolCatalog: toolCatalog).execute(
                toolCall,
                conversation: conversation,
                turn: turn
            )
            try store.completeToolCall(toolCall, output: output, turn: turn, conversation: conversation)
        } catch {
            if ConversationRunError.isCancellation(error) {
                try store.cancelToolCall(toolCall, conversation: conversation)
                throw LLMProviderError.cancelled
            }
            try store.failToolCall(toolCall, error: error, conversation: conversation)
            throw error
        }
    }
}
