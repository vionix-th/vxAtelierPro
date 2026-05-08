import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif
import SwiftData

/// Tests edge-cases and error-handling for ConversationItem and related models.
@MainActor
final class ConversationItemEdgeCaseTests: XCTestCase {
    var testEnv: TestEnvironment! = nil
    var context: ModelContext! = nil

    override func setUpWithError() throws {
        testEnv = TestEnvironment()
        context = testEnv.modelContext
    }

    override func tearDownWithError() throws {
        testEnv = nil
        context = nil
    }

    // Orphaned ConversationTurn test removed: ConversationTurn now requires a non-optional ConversationItem at compile time.
    // It is impossible to construct an orphaned turn; the Swift type system enforces this invariant.

    func testDuplicateTurnSequenceNumber() throws {
        XCTExpectFailure("Lacking mechanism")
        
        let conversation = testEnv.createConversation()
        let turn1 = ConversationTurn(sequenceNumber: 0, timestamp: Date(), userMessage: MessageItem(role: "user", text: "msg1", timestamp: Date(), toolCallId: nil), conversation: conversation)
        let turn2 = ConversationTurn(sequenceNumber: 0, timestamp: Date(), userMessage: MessageItem(role: "user", text: "msg2", timestamp: Date(), toolCallId: nil), conversation: conversation)
        conversation.turns = [turn1, turn2]
        context.insert(conversation)
        XCTAssertThrowsError(try context.save(), "Duplicate sequence numbers should not be allowed")
    }

    func testMessageItemMissingContent() throws {
        XCTExpectFailure("Lacking mechanism")
        
        let conversation = testEnv.createConversation()
        let msg = MessageItem(role: "user", text: "", timestamp: Date(), toolCallId: nil)
        let turn = ConversationTurn(sequenceNumber: 0, timestamp: Date(), userMessage: msg, conversation: conversation)
        conversation.turns = [turn]
        context.insert(conversation)
        XCTAssertThrowsError(try context.save(), "Empty message content should trigger validation error or rejection")
    }

    func testConversationOptionsAllowNoProviderConfiguration() throws {
        let options = ConversationOptions()
        context.insert(options)
        XCTAssertNoThrow(try context.save())
    }
}
