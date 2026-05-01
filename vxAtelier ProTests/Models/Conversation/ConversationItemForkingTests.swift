import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationItemForkingTests: XCTestCase {
    private var testEnv: TestEnvironment!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }
    
    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }
    
    func testForkingLogic() throws {
        let context = testEnv.modelContext
        let project = ProjectItem("Fork Project")
        let conversation = ConversationItem(timestamp: Date(), title: "Fork Source", options: ConversationOptions())
        conversation.project = project
        let userMsg1 = MessageItem(role: "user", text: "First", timestamp: Date(), toolCallId: nil)
        let userMsg2 = MessageItem(role: "user", text: "Second", timestamp: Date(), toolCallId: nil)
        let turn1 = ConversationTurn(sequenceNumber: 0, timestamp: Date(), userMessage: userMsg1, conversation: conversation)
        let turn2 = ConversationTurn(sequenceNumber: 1, timestamp: Date(), userMessage: userMsg2, conversation: conversation)
        conversation.turns.append(turn1)
        conversation.turns.append(turn2)
        context.insert(project)
        context.insert(conversation)
        try context.save()

        // Fork with no turns (upToTurnIndex: nil)
        let forkedNone = conversation.fork(upToTurnIndex: nil)
        XCTAssertEqual(forkedNone.title, "Fork Source (Fork)")
        XCTAssertEqual(forkedNone.turns.count, 0)
        XCTAssertEqual(forkedNone.project, project)

        // Fork up to first turn (inclusive)
        let forkedOne = conversation.fork(upToTurnIndex: 0)
        // Sort turns by sequenceNumber to mirror app logic (SwiftData relationships are unordered)
        let sortedForkedOneTurns = forkedOne.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        let sortedOrigTurns = conversation.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        XCTAssertEqual(sortedForkedOneTurns.count, 1)
        XCTAssertEqual(sortedForkedOneTurns[0].userMessage.displayText, "First")
        XCTAssertEqual(forkedOne.project, project)
        sortedForkedOneTurns[0].userMessage.setContentParts([MessageContentPartItem(index: 0, kind: .text, text: "Changed in Fork")])
        XCTAssertNotEqual(sortedForkedOneTurns[0].userMessage.displayText, sortedOrigTurns[0].userMessage.displayText)
        sortedForkedOneTurns[0].events.append(TurnEvent(type: .assistant, timestamp: Date(), message: MessageItem(role: "assistant", text: "Reply", timestamp: Date(), toolCallId: nil), turn: sortedForkedOneTurns[0]))
        XCTAssertNotEqual(sortedForkedOneTurns[0].events.count, sortedOrigTurns[0].events.count)

        // Fork up to second turn (inclusive)
        let forkedAll = conversation.fork(upToTurnIndex: 1)
        let sortedForkedAllTurns = forkedAll.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        XCTAssertEqual(sortedForkedAllTurns.count, 2)
        XCTAssertEqual(sortedForkedAllTurns[0].userMessage.displayText, "First")
        XCTAssertEqual(sortedForkedAllTurns[1].userMessage.displayText, "Second")
        XCTAssertEqual(forkedAll.project, project)
        sortedForkedAllTurns[1].userMessage.setContentParts([MessageContentPartItem(index: 0, kind: .text, text: "Changed in Fork All")])
        XCTAssertNotEqual(sortedForkedAllTurns[1].userMessage.displayText, sortedOrigTurns[1].userMessage.displayText)
    }
}
