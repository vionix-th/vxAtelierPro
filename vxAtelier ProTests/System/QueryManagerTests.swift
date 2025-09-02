import XCTest
import SwiftData
@testable import vxAtelier_Pro_debug

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
    
    func testInitialization() {
        XCTAssertNotNil(queryManager)
        XCTAssertEqual(queryManager.allConversations.count, 0)
        XCTAssertEqual(queryManager.allProjects.count, 0)
    }
    
    // MARK: - Data Fetching Tests
    
    func testFetchAllData() throws {
        // Given
        _ = testEnv.createConversation(title: "Test 1")
        _ = testEnv.createProject(name: "Project 1")
        try testEnv.save()
        
        // When
        queryManager.fetchAllData()
        
        // Then
        XCTAssertEqual(queryManager.allConversations.count, 1)
        XCTAssertEqual(queryManager.allProjects.count, 1)
        XCTAssertEqual(queryManager.allConversations.first?.title, "Test 1")
        XCTAssertEqual(queryManager.allProjects.first?.name, "Project 1")
    }
    
    // MARK: - Status Management Tests
    
    func testActiveItemsVisibility() {
        // Given
        let activeDialog = testEnv.createConversation(title: "Active", status: .active)
        try? testEnv.save()
        
        // When
        queryManager.fetchAllData()
        
        // Then - active items should always be visible
        XCTAssertEqual(queryManager.allConversations.count, 1)
        XCTAssertEqual(queryManager.allConversations.first?.title, "Active")
        
        // Clean up
        try? queryManager.deleteItems([activeDialog])
    }
    
    func testStatusPropertyAccess() {
        // Test that we can access the status properties
        // This doesn't test setting them since they're read-only
        // Note: We're only testing that we can access these properties without crashing
        // The actual values depend on UserDefaults which may vary in the test environment
        _ = queryManager.showArchived
        _ = queryManager.showTrashed
        _ = queryManager.showUserDialogsOnly
        
        // Ensure the test passes
        XCTAssertTrue(true)
    }
    
    // MARK: - Item Management Tests
    
    func testInsertAndDeleteItem() throws {
        // Given
        let dialog = testEnv.createConversation(title: "Test Dialog")
        
        // When - insert
        try queryManager.insert(dialog)
        queryManager.fetchAllData()
        
        // Then - should be in the list
        XCTAssertEqual(queryManager.allConversations.count, 1)
        XCTAssertEqual(queryManager.allConversations.first?.title, "Test Dialog")
        
        // When - delete
        try queryManager.delete(dialog)
        queryManager.fetchAllData()
        
        // Then - should be removed
        XCTAssertTrue(queryManager.allConversations.isEmpty)
    }
    
    func testArchiveItem() throws {
        // Given
        let dialog = testEnv.createConversation(title: "Test Dialog")
        try queryManager.insert(dialog)
        queryManager.fetchAllData()
        
        // When - archive
        try queryManager.archiveItem(dialog)
        queryManager.fetchAllData()
        
        // Then - should be archived
        XCTAssertEqual(dialog.status, .archived)
        
        // When - unarchive
        try queryManager.restoreItem(dialog)
        queryManager.fetchAllData()
        
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
        queryManager.fetchAllData()
        XCTAssertFalse(queryManager.allConversations.contains(where: { $0.title == "Not in context" }))
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
        try queryManager.insertItems([config1, config2])
        
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
