import XCTest
@testable import vxAtelier_Pro_debug
import SwiftData

/// Performance and scalability tests for ConversationItem and related models.
@MainActor
final class ConversationItemScalabilityTests: XCTestCase {
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

    func testInsertLargeNumberOfConversations() throws {
        let conversationCount = 5000
        let turnCount = 5
        let start = Date()
        for i in 0..<conversationCount {
            let conversation = testEnv.createConversation(title: "Conv_\(i)")
            conversation.turns = (0..<turnCount).map { t in
                ConversationTurn(
                    sequenceNumber: t,
                    timestamp: Date(),
                    userMessage: MessageItem(role: "user", content: ContentItem("msg_\(t)"), timestamp: Date(), toolCallId: nil, toolCallsData: nil),
                    conversation: conversation
                )
            }
            context.insert(conversation)
        }
        try context.save()
        let elapsed = Date().timeIntervalSince(start)
        print("Inserted \(conversationCount) conversations (\(turnCount) turns each) in \(elapsed) seconds")
        XCTAssertLessThan(elapsed, 30.0, "Bulk insert should complete in under 30 seconds")
    }

    func testFetchPerformanceLargeConversationSet() throws {
        let conversationCount = 1000
        let turnCount = 10
        for i in 0..<conversationCount {
            let conversation = testEnv.createConversation(title: "FetchConv_\(i)")
            conversation.turns = (0..<turnCount).map { t in
                ConversationTurn(
                    sequenceNumber: t,
                    timestamp: Date(),
                    userMessage: MessageItem(role: "user", content: ContentItem("msg_\(t)"), timestamp: Date(), toolCallId: nil, toolCallsData: nil),
                    conversation: conversation
                )
            }
            context.insert(conversation)
        }
        try context.save()
        let start = Date()
        let fetchDescriptor = FetchDescriptor<ConversationItem>()
        let results = try context.fetch(fetchDescriptor)
        let elapsed = Date().timeIntervalSince(start)
        print("Fetched \(results.count) conversations in \(elapsed) seconds")
        XCTAssertEqual(results.count, conversationCount)
        XCTAssertLessThan(elapsed, 5.0, "Bulk fetch should complete in under 5 seconds")
    }
}
