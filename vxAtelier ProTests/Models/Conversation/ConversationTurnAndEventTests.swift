import XCTest
import SwiftData
@testable import vxAtelier_Pro_debug

@MainActor
final class ConversationTurnAndEventTests: XCTestCase {
    private var testEnv: TestEnvironment!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }
    
    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }
    
    // MARK: - Sequence and Basic CRUD
    func testTurnSequenceAndPersistence() throws {
        let context = testEnv.modelContext
        let conversation = testEnv.createConversation()
        let msg1 = MessageItem(role: "user", content: ContentItem("A"), timestamp: Date())
        let msg2 = MessageItem(role: "user", content: ContentItem("B"), timestamp: Date())
        let turn1 = ConversationTurn(sequenceNumber: 1, userMessage: msg1, conversation: conversation)
        let turn2 = ConversationTurn(sequenceNumber: 2, userMessage: msg2, conversation: conversation)
        conversation.turns = [turn1, turn2]
        context.insert(conversation)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<ConversationItem>()).filter({$0.id == conversation.id }).first!
        let sortedTurns = fetched.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        XCTAssertEqual(sortedTurns.count, 2)
        XCTAssertEqual(sortedTurns[0].sequenceNumber, 1)
        XCTAssertEqual(sortedTurns[1].sequenceNumber, 2)
    }

    // MARK: - Event Management
    func testTurnEventCRUDAndOrdering() throws {
        let context = testEnv.modelContext
        let msg = MessageItem(role: "user", content: ContentItem("Prompt"), timestamp: Date())
        let conversation = testEnv.createConversation()
let turn = ConversationTurn(sequenceNumber: 1, userMessage: msg, conversation: conversation)
let event1 = TurnEvent(type: .assistant, timestamp: Date().addingTimeInterval(-10), message: msg, turn: turn)
let event2 = TurnEvent(type: .toolCall, timestamp: Date(), message: msg, turn: turn)
turn.events = [event1, event2]
conversation.turns.append(turn)
context.insert(conversation)
try context.save()
        let fetched = try context.fetch(
            FetchDescriptor<ConversationTurn>(predicate: #Predicate { $0.sequenceNumber == 1 })
        ).first!
        let sortedEvents = fetched.events.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(sortedEvents.count, 2)
        XCTAssertEqual(sortedEvents[0].type, TurnEvent.EventType.assistant)
        XCTAssertEqual(sortedEvents[1].type, TurnEvent.EventType.toolCall)
    }

    // MARK: - Orphaning and Nullify
    // Orphaned ConversationTurn test removed: ConversationTurn now requires a non-optional ConversationItem at compile time.
    // It is impossible to construct an orphaned turn; the Swift type system enforces this invariant.

    // MARK: - Cascade Delete
    func testCascadeDeleteRemovesEvents() throws {
        let context = testEnv.modelContext
        let msg = MessageItem(role: "user", content: ContentItem("Prompt"), timestamp: Date())
        let conversation = testEnv.createConversation()
let turn = ConversationTurn(sequenceNumber: 1, userMessage: msg, conversation: conversation)
let event = TurnEvent(type: .assistant, message: msg, turn: turn)
turn.events = [event]
conversation.turns.append(turn)
context.insert(conversation)
try context.save()
let eventId = event.id
context.delete(turn)
try context.save()
let remaining = try context.fetch(FetchDescriptor<TurnEvent>())
XCTAssertFalse(remaining.contains { $0.id == eventId })
    }

    // MARK: - Edge Cases
    func testDuplicateTurnSequenceNumbers() {
        let msg = MessageItem(role: "user", content: ContentItem("Prompt"), timestamp: Date())
        let conversation = testEnv.createConversation()
let turn1 = ConversationTurn(sequenceNumber: 1, userMessage: msg, conversation: conversation)
let turn2 = ConversationTurn(sequenceNumber: 1, userMessage: msg, conversation: conversation)
XCTAssertEqual(turn1.sequenceNumber, turn2.sequenceNumber)
    }
    
    func testInvalidEventType() {
        // Enum raw value init returns nil for unknown type
        let invalid = TurnEvent.EventType(rawValue: "invalid")
        XCTAssertNil(invalid)
    }
}
