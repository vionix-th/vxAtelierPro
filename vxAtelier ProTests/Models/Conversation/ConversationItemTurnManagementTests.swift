import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationItemTurnManagementTests: XCTestCase {
    private var testEnv: TestEnvironment!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }
    
    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }
    
    func testAddTurn() {
        let conversation = testEnv.createConversation()
        let userMessage = MessageItem(
            role: "user",
            content: ContentItem("Hello, world!"),
            timestamp: Date(),
            toolCallId: nil,
            toolCallsData: nil
        )
        let turn = ConversationTurn(
            sequenceNumber: 0,
            timestamp: Date(),
            userMessage: userMessage,
            conversation: conversation
        )
        conversation.turns.append(turn)
        XCTAssertEqual(conversation.turns.count, 1)
        // Sort turns by sequenceNumber to mirror app logic (SwiftData relationships are unordered)
        let sortedTurns = conversation.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        XCTAssertEqual(sortedTurns.first?.userMessage.content.text, "Hello, world!")
    }
    
    func testAddMultipleTurns() throws {
        let context = testEnv.modelContext
        let conversation = ConversationItem(timestamp: Date(), title: "Multi-Turn", options: ConversationOptions())
        let userMsg1 = MessageItem(role: "user", content: ContentItem("First"), timestamp: Date(), toolCallId: nil, toolCallsData: nil)
        let userMsg2 = MessageItem(role: "user", content: ContentItem("Second"), timestamp: Date(), toolCallId: nil, toolCallsData: nil)
        let turn1 = ConversationTurn(sequenceNumber: 0, timestamp: Date(), userMessage: userMsg1, conversation: conversation)
        let turn2 = ConversationTurn(sequenceNumber: 1, timestamp: Date(), userMessage: userMsg2, conversation: conversation)
        conversation.turns.append(turn1)
        conversation.turns.append(turn2)
        context.insert(conversation)
        try context.save()
        XCTAssertEqual(conversation.turns.count, 2)
        // Sort turns by sequenceNumber to mirror app logic (SwiftData relationships are unordered)
        let sortedTurns = conversation.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        XCTAssertEqual(sortedTurns[0].userMessage.content.text, "First")
        XCTAssertEqual(sortedTurns[1].userMessage.content.text, "Second")
        XCTAssert(sortedTurns[0].sequenceNumber < sortedTurns[1].sequenceNumber)
    }
    
    func testEditTurn() throws {
        let context = testEnv.modelContext
        let conversation = ConversationItem(timestamp: Date(), title: "Edit Turn", options: ConversationOptions())
        let userMsg = MessageItem(role: "user", content: ContentItem("Original"), timestamp: Date(), toolCallId: nil, toolCallsData: nil)
        let turn = ConversationTurn(sequenceNumber: 0, timestamp: Date(), userMessage: userMsg, conversation: conversation)
        conversation.turns.append(turn)
        context.insert(conversation)
        try context.save()
        turn.userMessage.content = ContentItem("Edited")
        try context.save()
        let fetchTurns = try context.fetch(FetchDescriptor<ConversationTurn>())
        let fetched = fetchTurns.first { $0.id == turn.id }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.userMessage.content.text, "Edited")
    }
    
    func testDeleteSpecificTurn() throws {
        let context = testEnv.modelContext
        let conversation = ConversationItem(timestamp: Date(), title: "Delete Turn", options: ConversationOptions())
        let userMsg1 = MessageItem(role: "user", content: ContentItem("Keep"), timestamp: Date(), toolCallId: nil, toolCallsData: nil)
        let userMsg2 = MessageItem(role: "user", content: ContentItem("Delete Me"), timestamp: Date(), toolCallId: nil, toolCallsData: nil)
        let turn1 = ConversationTurn(sequenceNumber: 0, timestamp: Date(), userMessage: userMsg1, conversation: conversation)
        let turn2 = ConversationTurn(sequenceNumber: 1, timestamp: Date(), userMessage: userMsg2, conversation: conversation)
        conversation.turns.append(turn1)
        conversation.turns.append(turn2)
        context.insert(conversation)
        try context.save()
        if let idx = conversation.turns.firstIndex(where: { $0.userMessage.content.text == "Delete Me" }) {
            let toDelete = conversation.turns.remove(at: idx)
            context.delete(toDelete)
        }
        try context.save()
        let fetchTurns = try context.fetch(FetchDescriptor<ConversationTurn>())
        XCTAssertEqual(fetchTurns.count, 1)
        // Sort fetchTurns by sequenceNumber to mirror app logic (SwiftData relationships are unordered)
        let sortedFetchTurns = fetchTurns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        XCTAssertEqual(sortedFetchTurns.first?.userMessage.content.text, "Keep")
    }
}
