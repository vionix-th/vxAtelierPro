import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationItemScaleIntegrationTests: XCTestCase {
    private var testEnv: TestEnvironment!
    private var context: ModelContext!

    override func setUpWithError() throws {
        testEnv = TestEnvironment()
        context = testEnv.modelContext
    }

    override func tearDownWithError() throws {
        context = nil
        testEnv = nil
    }

    func testPersistsLargeConversationSetWithTurns() throws {
        let conversationCount = 250
        let turnCount = 3

        for conversationIndex in 0..<conversationCount {
            let conversation = ConversationItem(
                timestamp: Date(timeIntervalSince1970: TimeInterval(conversationIndex)),
                title: "Scale Conversation \(conversationIndex)",
                options: ConversationOptions()
            )
            conversation.turns = (0..<turnCount).map { turnIndex in
                ConversationTurn(
                    sequenceNumber: turnIndex,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(conversationIndex * 10 + turnIndex)),
                    userMessage: MessageItem(role: "user", text: "message \(turnIndex)"),
                    conversation: conversation
                )
            }
            context.insert(conversation)
        }

        try context.save()

        let conversations = try context.fetch(FetchDescriptor<ConversationItem>())
        let turns = try context.fetch(FetchDescriptor<ConversationTurn>())
        XCTAssertEqual(conversations.count, conversationCount)
        XCTAssertEqual(turns.count, conversationCount * turnCount)
        XCTAssertTrue(conversations.allSatisfy { $0.turns.count == turnCount })
    }

    func testFetchDescriptorLimitAndSortHandlesLargeConversationSet() throws {
        for index in 0..<300 {
            context.insert(ConversationItem(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                title: "Fetch Conversation \(index)",
                options: ConversationOptions()
            ))
        }
        try context.save()

        var descriptor = FetchDescriptor<ConversationItem>(
            sortBy: [SortDescriptor(\ConversationItem.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 10

        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 10)
        XCTAssertEqual(results.first?.title, "Fetch Conversation 299")
        XCTAssertEqual(results.last?.title, "Fetch Conversation 290")
    }
}
