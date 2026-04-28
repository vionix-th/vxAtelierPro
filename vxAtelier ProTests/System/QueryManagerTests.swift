import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class QueryManagerTests: XCTestCase {
    private var testEnv: TestEnvironment!
    private var queryManager: QueryManager!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
        queryManager = testEnv.createQueryManager()
    }
    
    override func tearDown() {
        queryManager = nil
        testEnv = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() throws {
        XCTAssertNotNil(queryManager)
        XCTAssertEqual(try testEnv.conversations().count, 0)
        XCTAssertEqual(try testEnv.projects().count, 0)
    }
    
    // MARK: - Data Fetching Tests
    
    func testFetchAllData() throws {
        // Given
        _ = testEnv.createConversation(title: "Test 1")
        _ = testEnv.createProject(name: "Project 1")
        try testEnv.save()
        
        // Then
        let conversations = try testEnv.conversations()
        let projects = try testEnv.projects()
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(conversations.first?.title, "Test 1")
        XCTAssertEqual(projects.first?.name, "Project 1")
    }
    
    // MARK: - Status Management Tests
    
    func testActiveItemsVisibility() throws {
        // Given
        let activeDialog = testEnv.createConversation(title: "Active", status: .active)
        try testEnv.save()
        
        // Then - active items should always be visible
        let conversations = try testEnv.conversations()
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.title, "Active")
        
        // Clean up
        try queryManager.deleteItems([activeDialog])
    }
    
    func testStandaloneAndSystemConversationFilteringByContentFilter() throws {
        // Given
        let project = testEnv.createProject(name: "Project 1")
        _ = testEnv.createConversation(title: "Active", status: .active, purpose: .user)
        _ = testEnv.createConversation(title: "Archived", status: .archived, purpose: .user)
        _ = testEnv.createConversation(title: "Trashed", status: .trashed, purpose: .user)
        _ = testEnv.createConversation(title: "System Archived", status: .archived, purpose: .system)
        _ = testEnv.createConversation(
            title: "Project Dialog",
            status: .active,
            purpose: .user,
            project: project
        )
        try testEnv.save()

        // Then - standalone conversations are filtered by status and exclude system/project items
        let activeStandalone = try testEnv.standaloneConversations(
            showSystemConversations: false,
            contentFilter: .active
        )
        XCTAssertEqual(activeStandalone.map(\.title), ["Active"])

        let archivedStandalone = try testEnv.standaloneConversations(
            showSystemConversations: false,
            contentFilter: .archived
        )
        XCTAssertEqual(archivedStandalone.map(\.title), ["Archived"])

        let trashedStandalone = try testEnv.standaloneConversations(
            showSystemConversations: false,
            contentFilter: .trashed
        )
        XCTAssertEqual(trashedStandalone.map(\.title), ["Trashed"])

        // System conversations are included in standalone when enabled
        let archivedStandaloneWithSystem = try testEnv.standaloneConversations(
            showSystemConversations: true,
            contentFilter: .archived
        )
        XCTAssertEqual(
            Set(archivedStandaloneWithSystem.map(\.title)),
            Set(["Archived", "System Archived"])
        )
    }
    
    // MARK: - Item Management Tests
    
    func testInsertAndDeleteItem() throws {
        // Given
        let dialog = testEnv.createConversation(title: "Test Dialog")
        
        // When - insert
        try queryManager.insert(dialog)
        
        // Then - should be in the list
        var conversations = try testEnv.conversations()
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.title, "Test Dialog")
        
        // When - delete
        try queryManager.delete(dialog)
        
        // Then - should be removed
        conversations = try testEnv.conversations()
        XCTAssertTrue(conversations.isEmpty)
    }
    
    func testArchiveItem() throws {
        // Given
        let dialog = testEnv.createConversation(title: "Test Dialog")
        try queryManager.insert(dialog)
        
        // When - archive
        try queryManager.archiveItem(dialog)
        
        // Then - should be archived
        XCTAssertEqual(dialog.status, .archived)
        
        // When - unarchive
        try queryManager.restoreItem(dialog)
        
        // Then - should be active again
        XCTAssertEqual(dialog.status, .active)
        
        // Clean up
        try queryManager.delete(dialog)
    }
    
    // MARK: - Error Handling Tests
    
    func testDeleteNonExistentItem() throws {
        // Given
        let options = ConversationOptions()
        let dialog = ConversationItem(timestamp: Date(), title: "Not in context", options: options)
        
        // When/Then - should not throw when deleting non-existent item
        // The current implementation of deleteItems doesn't throw for non-existent items
        // It just attempts to delete and save
        XCTAssertNoThrow(try queryManager.deleteItems([dialog]))
        
        // Verify the item wasn't added to the context
        let conversations = try testEnv.conversations()
        XCTAssertFalse(conversations.contains(where: { $0.title == "Not in context" }))
    }
    
    func testArchiveNonModifiableItem() throws {
        // Given - Create a non-modifiable item (e.g., BookmarkItem)
        let options = ConversationOptions()
        let dialog = ConversationItem(timestamp: Date(), title: "Test Dialog", options: options)
        try queryManager.insert(dialog)
        
        // Create necessary message item for the bookmark
        let contentItem = ContentItem("Test message content")
        let messageItem = MessageItem(role: "user", content: contentItem)
        
        // Create the turn for the message
        let turn = ConversationTurn(sequenceNumber: 0, userMessage: messageItem, conversation: dialog)
        dialog.turns.append(turn)
        try queryManager.insert(dialog)
        // Create the bookmark with the turn
        let nonModifiable = BookmarkItem("Test Bookmark", turn: turn)
        
        // When/Then - should throw when trying to archive non-modifiable item
        XCTAssertThrowsError(try queryManager.archiveItem(nonModifiable), "Should throw an error when archiving non-modifiable item") { error in
            XCTAssertTrue(error is AppError)
        }
    }
    
    // MARK: - Default Configuration Tests
    
    func testDefaultApiConfiguration() throws {
        // Given
        let config1 = APIConfigurationItem(name: "Config 1", 
                                         baseURL: "https://api.example.com",
                                         isDefault: false)
        let config2 = APIConfigurationItem(name: "Config 2", 
                                         baseURL: "https://api2.example.com",
                                         isDefault: true)
        
        // When - insert configurations
        try queryManager.insert(config1)
        try queryManager.insert(config2)
        
        // Then - should return the default configuration
        XCTAssertEqual(queryManager.defaultApiConfiguration?.name, "Config 2")
        
        // When - change default
        config1.isDefault = true
        config2.isDefault = false
        try queryManager.saveContext()
        
        // Then - should update the default configuration
        XCTAssertEqual(queryManager.defaultApiConfiguration?.name, "Config 1")
        
        // Clean up
        try queryManager.deleteItems([config1, config2])
    }
}
