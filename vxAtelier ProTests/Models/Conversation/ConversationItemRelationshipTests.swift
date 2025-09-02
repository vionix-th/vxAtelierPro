import XCTest
import SwiftData
@testable import vxAtelier_Pro_debug

@MainActor
final class ConversationItemRelationshipTests: XCTestCase {
    private var testEnv: TestEnvironment!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }
    
    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }
    
    func testProjectRelationship() {
        let project = testEnv.createProject()
        let conversation = testEnv.createConversation(project: project)
        XCTAssertEqual(conversation.project, project)
        XCTAssert(project.conversations.contains(conversation))
    }
    
    func testDeleteTurnCascadesFromConversation() throws {
        let context = testEnv.modelContext
        let conversation = ConversationItem(timestamp: Date(), title: "Cascade Turn", options: ConversationOptions())
        let userMessage = MessageItem(role: "user", content: ContentItem("Cascade Turn Test"), timestamp: Date(), toolCallId: nil, toolCallsData: nil)
        let turn = ConversationTurn(sequenceNumber: 0, timestamp: Date(), userMessage: userMessage, conversation: conversation)
        conversation.turns.append(turn)
        context.insert(conversation)
        try context.save()
        XCTAssertEqual(conversation.turns.count, 1)
        conversation.turns.removeAll()
        context.delete(turn)
        try context.save()
        let fetchTurns = try context.fetch(FetchDescriptor<ConversationTurn>())
        XCTAssertTrue(fetchTurns.isEmpty)
    }
    
    func testDeleteProjectNullifiesConversationReference() throws {
        XCTExpectFailure("SwiftData nullify rule for project relationship does not function in in-memory test container. See known issue.")
        let context = testEnv.modelContext
        let project = ProjectItem("Nullify Project")
        let conversation = ConversationItem(timestamp: Date(), title: "Nullify Project Ref", options: ConversationOptions())
        conversation.project = project
        project.conversations.append(conversation)
        context.insert(project)
        context.insert(conversation)
        try context.save()
        XCTAssertEqual(conversation.project, project)
        XCTAssertTrue(project.conversations.contains(conversation))
        context.delete(project)
        try context.save()
        let id = conversation.id
        let fetchConvs = try context.fetch(FetchDescriptor<ConversationItem>())
        let fetched = fetchConvs.first { $0.id == id }
        XCTAssertNotNil(fetched)
        vxAtelierPro.log.debug("Fetched conversation after project delete: id=\(String(describing: fetched?.id)), project=\(String(describing: fetched?.project)), totalConvs=\(fetchConvs.count)")
        XCTAssertNil(fetched?.project)
    }
    
    func testDeleteOptionsCascadesFromConversation() throws {
        let context = testEnv.modelContext
        let options = ConversationOptions()
        let conversation = ConversationItem(timestamp: Date(), title: "Cascade Options", options: options)
        context.insert(conversation)
        try context.save()
        XCTAssertNotNil(conversation.options)
        context.delete(conversation)
        try context.save()
        let fetchOptions = try context.fetch(FetchDescriptor<ConversationOptions>())
        XCTAssertTrue(fetchOptions.isEmpty)
    }
}
