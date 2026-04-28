import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

import Foundation

// Backup/restore roundtrip tests for ConversationItem using ConversationExportData and FullBackup
@MainActor
final class ConversationItemBackupRestoreTests: XCTestCase {
    var testEnv: TestEnvironment!
    var context: ModelContext { testEnv.modelContext }

    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }

    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }

    func testConversationItemBackupRestoreRoundtrip() throws {
        // Use a fixed timestamp for deterministic roundtrip
        let fixedTimestamp = Date()
        // Create a conversation with nested turns, options, and parameters
        let conversation = testEnv.createConversation(timestamp: fixedTimestamp)
        conversation.title = "Backup/Restore Dialog"
        conversation.tokenCount = 123
        conversation.usedTokenCount = 99
        conversation.purpose = .system
        conversation.status = .archived
        conversation.timestamp = fixedTimestamp

        // Add a turn with a user message and an event, all with fixed timestamp
        let userMessage = MessageItem(role: "user", content: ContentItem("Test message"), timestamp: fixedTimestamp, toolCallId: nil, toolCallsData: nil)
        let turn = ConversationTurn(sequenceNumber: 0, timestamp: fixedTimestamp, userMessage: userMessage, conversation: conversation)
        let eventMessage = MessageItem(role: "assistant", content: ContentItem("Assistant reply"), timestamp: fixedTimestamp, toolCallId: nil, toolCallsData: nil)
        let event = TurnEvent(type: .assistant, timestamp: fixedTimestamp, message: eventMessage, turn: turn)
        turn.events.append(event)
        conversation.turns.append(turn)

        context.insert(conversation)
        try context.save()

        // Export to DTO
        let dto = ConversationExportData(conversation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dto)

        // Import from DTO
        let decoder = JSONDecoder()
        let decodedDTO = try decoder.decode(ConversationExportData.self, from: data)
        let restored = try decodedDTO.toDataItem(context: context)

        // Assert deep equivalence (excluding persistent IDs)
        XCTAssertEqual(restored.title, conversation.title)
        XCTAssertEqual(restored.timestamp.timeIntervalSince1970, conversation.timestamp.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(restored.tokenCount, conversation.tokenCount)
        XCTAssertEqual(restored.usedTokenCount, conversation.usedTokenCount)
        XCTAssertEqual(restored.purpose, conversation.purpose)
        XCTAssertEqual(restored.status, conversation.status)
        // Sort turns by sequenceNumber to mirror app logic (SwiftData relationships are unordered)
        let sortedRestoredTurns = restored.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        let sortedOriginalTurns = conversation.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        XCTAssertEqual(sortedRestoredTurns.count, sortedOriginalTurns.count)
        XCTAssertEqual(sortedRestoredTurns[0].userMessage.content.text, sortedOriginalTurns[0].userMessage.content.text)
        // Sort events by timestamp to mirror app logic
        let sortedRestoredEvents = sortedRestoredTurns[0].events.sorted { $0.timestamp < $1.timestamp }
        let sortedOriginalEvents = sortedOriginalTurns[0].events.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(sortedRestoredEvents.count, sortedOriginalEvents.count)
        XCTAssertEqual(sortedRestoredEvents[0].message.content.text, sortedOriginalEvents[0].message.content.text)
        // Options and parameters: sort by name for deterministic comparison
        let sortedRestoredParams = restored.options.parameters.sorted { $0.name < $1.name }
        let sortedOriginalParams = conversation.options.parameters.sorted { $0.name < $1.name }
        XCTAssertEqual(sortedRestoredParams.count, sortedOriginalParams.count)
        for (a, b) in zip(sortedRestoredParams, sortedOriginalParams) {
            XCTAssertEqual(a.name, b.name)
            XCTAssertEqual(a.valueType, b.valueType)
            // Value comparison is type-dependent, so basic string comparison
            XCTAssertEqual(String(describing: a.value), String(describing: b.value))
        }
    }
}
