import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class LLMToolExecutionCoordinatorTests: LLMTestCase {
    func testConfigurableToolDefaultsRoundTripThroughConversationOptions() throws {
        let options = ConversationOptions(shouldSetupParameters: false)
        let defaults = ListShortcutsTool().defaultConfiguration()

        options.setToolConfiguration("list_shortcuts", configuration: defaults)

        let restored = try XCTUnwrap(options.getToolConfiguration("list_shortcuts"))
        XCTAssertEqual(restored["Restricted"]?.boolValue, false)
        XCTAssertEqual(restored["RestrictedList"]?.objectValue?["ID0001"]?.stringValue, "Shortcut Name A")
    }

    func testNonConfigurableToolDoesNotExposeConfiguration() {
        XCTAssertNil(RunShortcutTool() as? any ConfigurableAITool)
    }

    func testSuccessfulToolExecutionUsesTypedCallAndEmptyDefaultConfiguration() async throws {
        AIToolRegistry.shared.registerTool(UnitEchoTool())
        let fixture = makeToolExecutionFixture(toolName: UnitEchoTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitEchoTool.toolName, enabled: true)

        try await LLMToolExecutionCoordinator().execute([toolCall], conversation: conversation, turn: turn)

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
        let call = ToolExecutionCall(
            id: "call_shortcuts",
            name: "list_shortcuts",
            argumentsJSON: "{}",
            configuration: [
                "Restricted": .boolean(true),
                "RestrictedList": .object([
                    "ID0001": .string("Shortcut Name A")
                ])
            ],
            context: ToolExecutionContext(conversation: conversation, turn: turn)
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

        await assertThrowsAsyncError(try await LLMToolExecutionCoordinator().execute([toolCall], conversation: conversation, turn: turn)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool '\(UnitEchoTool.toolName)' is not enabled."))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool '\(UnitEchoTool.toolName)' is not enabled.")
    }

    func testMissingToolCallFailsAndPersistsFailedStatus() async throws {
        let missingToolName = "unit_missing_tool"
        let fixture = makeToolExecutionFixture(toolName: missingToolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(missingToolName, enabled: true)

        await assertThrowsAsyncError(try await LLMToolExecutionCoordinator().execute([toolCall], conversation: conversation, turn: turn)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool not found: \(missingToolName)"))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool not found: \(missingToolName)")
    }

    func testNonExecutableToolCallFailsAndPersistsFailedStatus() async throws {
        AIToolRegistry.shared.registerTool(UnitSchemaOnlyTool())
        let fixture = makeToolExecutionFixture(toolName: UnitSchemaOnlyTool.toolName)
        let conversation = fixture.conversation
        let turn = fixture.turn
        let toolCall = fixture.toolCall
        conversation.options.setToolEnabled(UnitSchemaOnlyTool.toolName, enabled: true)

        await assertThrowsAsyncError(try await LLMToolExecutionCoordinator().execute([toolCall], conversation: conversation, turn: turn)) { error in
            XCTAssertEqual(error as? LLMProviderError, .unsupportedCapability("Tool execution not supported: \(UnitSchemaOnlyTool.toolName)"))
        }

        XCTAssertEqual(toolCall.status, .failed)
        XCTAssertEqual(toolCall.errorMessage, "Tool execution not supported: \(UnitSchemaOnlyTool.toolName)")
    }
}
