import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ConversationItemStatusUpdateTests: XCTestCase {
    private var testEnv: TestEnvironment!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }
    
    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }
    
    func testArchive() {
        let conversation = testEnv.createConversation()
        conversation.status = .archived
        XCTAssertEqual(conversation.status, .archived)
    }
    
    func testTrash() {
        let conversation = testEnv.createConversation()
        conversation.status = .trashed
        XCTAssertEqual(conversation.status, .trashed)
    }
    
    func testUpdateProperties() {
        let conversation = testEnv.createConversation()
        let newTitle = "Updated Title"
        let newTimestamp = Date()
        let newTokenCount = 100
        let newUsedTokenCount = 50
        conversation.title = newTitle
        conversation.timestamp = newTimestamp
        conversation.tokenCount = newTokenCount
        conversation.usedTokenCount = newUsedTokenCount
        conversation.purpose = .system
        XCTAssertEqual(conversation.title, newTitle)
        XCTAssertEqual(conversation.timestamp, newTimestamp)
        XCTAssertEqual(conversation.tokenCount, newTokenCount)
        XCTAssertEqual(conversation.usedTokenCount, newUsedTokenCount)
        XCTAssertEqual(conversation.purpose, .system)
    }
}
