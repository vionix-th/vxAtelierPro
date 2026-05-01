import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class QueryManagerDeletionTests: XCTestCase {
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
    
    // MARK: - Reference Integrity Tests
    
    func testDeleteDialogNullifyingProjectReference() throws {
        // Given - Create a dialog and associate it with a project
        let project = testEnv.createProject(name: "Test Project")
        let dialog = testEnv.createConversation(title: "Test Dialog")
        dialog.project = project
        project.conversations.append(dialog)
        try testEnv.save()
        
        // Verify the initial relationship
        XCTAssertEqual(dialog.project?.persistentModelID, project.persistentModelID)
        XCTAssertTrue(project.conversations.contains(where: { $0.persistentModelID == dialog.persistentModelID }))
        XCTAssertEqual(project.conversations.count, 1)
        
        // When - Delete the dialog
        try queryManager.delete(dialog)
        
        // Then - Project should still exist but with empty dialogs array
        let updatedProject = try testEnv.projects().first { $0.persistentModelID == project.persistentModelID }
        XCTAssertNotNil(updatedProject, "Project should still exist after dialog deletion")
        XCTAssertEqual(updatedProject?.conversations.count, 0, "Project should have no dialogs after dialog deletion")
    }
    
    func testDeleteProjectCascadeToDialogs() throws {
        // Given - Create a project with multiple dialogs
        let project = testEnv.createProject(name: "Test Project")
        let dialog1 = testEnv.createConversation(title: "Dialog 1")
        let dialog2 = testEnv.createConversation(title: "Dialog 2")
        dialog1.project = project
        dialog2.project = project
        project.conversations.append(dialog1)
        project.conversations.append(dialog2)
        try testEnv.save()
        
        // Initial state verification
        XCTAssertEqual(try testEnv.projects().count, 1)
        XCTAssertEqual(try testEnv.conversations().count, 2)
        
        // When - Delete the project using deleteItemPermanently which handles cascades
        try queryManager.deleteItemPermanently(project)
        
        // Then - Both project and its dialogs should be deleted
        XCTAssertEqual(try testEnv.projects().count, 0, "Project should be deleted")
        XCTAssertEqual(try testEnv.conversations().count, 0, "All associated dialogs should be deleted")
    }
    
    func testDeleteAPIConfigurationWithCleanupReferences() throws {
        // Given - Create configuration referenced by dialog and project
        let config = APIConfigurationItem(name: "Test API", apiKey: "key", baseURL: "https://api.test.com")
        let dialog = testEnv.createConversation(title: "Dialog with API")
        let project = testEnv.createProject(name: "Project with API")
        
        dialog.options.apiConfiguration = config
        project.defaultOptions.apiConfiguration = config
        try queryManager.insert(config)
        try queryManager.saveContext()
        
        // Verify initial relationships
        XCTAssertEqual(dialog.options.apiConfiguration?.persistentModelID, config.persistentModelID)
        XCTAssertEqual(project.defaultOptions.apiConfiguration?.persistentModelID, config.persistentModelID)
        
        // When - Cleanup references for config (simulating backup restoration scenario)
        try queryManager.cleanupReferences(for: config)
        
        // Then - References should be nullified
        let updatedDialog = try testEnv.conversations().first { $0.persistentModelID == dialog.persistentModelID }
        let updatedProject = try testEnv.projects().first { $0.persistentModelID == project.persistentModelID }
        
        XCTAssertNotNil(updatedDialog)
        XCTAssertNotNil(updatedProject)
        XCTAssertNil(updatedDialog?.options.apiConfiguration, "Dialog API configuration reference should be nullified")
        XCTAssertNil(updatedProject?.defaultOptions.apiConfiguration, "Project API configuration reference should be nullified")
    }
    
    // MARK: - Concurrent Operation Tests
    
    func testSequentialDeletions() throws {
        // Given - Create multiple objects
        let dialogs = (1...5).map { testEnv.createConversation(title: "Dialog \($0)") }
        try testEnv.save()
        
        // Initial state verification
        XCTAssertEqual(try testEnv.conversations().count, 5)
        
        // When - Delete each dialog one by one
        for dialog in dialogs {
            try queryManager.delete(dialog)
            // Verify after each deletion
            let conversations = try testEnv.conversations()
            XCTAssertFalse(conversations.contains { $0.persistentModelID == dialog.persistentModelID },
                           "Dialog should be removed after deletion")
        }
        
        // Then - All dialogs should be deleted
        XCTAssertEqual(try testEnv.conversations().count, 0, "All dialogs should be deleted")
    }
    
    func testDeleteThenImmediateFetch() throws {
        // Given - Create test data
        let dialog = testEnv.createConversation(title: "Test Dialog")
        try queryManager.insert(dialog)
        
        // Verify initial state
        XCTAssertEqual(try testEnv.conversations().count, 1)
        
        // When - Delete and immediately fetch
        try queryManager.delete(dialog)
        
        // Then - Dialog should be gone from fetched results
        XCTAssertEqual(try testEnv.conversations().count, 0)
        
        // Create a new dialog with the same title to verify we can re-add after deletion
        let newDialog = testEnv.createConversation(title: "Test Dialog")
        try queryManager.insert(newDialog)
        
        // Then - New dialog should be added successfully
        let conversations = try testEnv.conversations()
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.title, "Test Dialog")
        XCTAssertNotEqual(conversations.first?.persistentModelID, dialog.persistentModelID)
    }
    
    // MARK: - Edge Case Tests
    
    func testDeleteUnsavedObject() throws {
        // Given - Create object but don't save it
        let dialog = testEnv.createConversation(title: "Unsaved Dialog")
        // Do NOT insert/save the dialog
        
        // When/Then - Attempt to delete unsaved object
        XCTAssertNoThrow(try queryManager.delete(dialog), "Deleting unsaved object should not throw")
        
        // Verify no state change
        XCTAssertEqual(try testEnv.conversations().count, 0)
    }
    
    func testDeleteObjectAfterRelationshipModification() throws {
        // Given - Create related objects
        let project = testEnv.createProject(name: "Test Project")
        let dialog = testEnv.createConversation(title: "Test Dialog")
        try testEnv.save()
        
        // Modify relationship
        dialog.project = project
        project.conversations.append(dialog)
        try testEnv.save()
        
        // Verify initial relationship
        XCTAssertEqual(dialog.project?.persistentModelID, project.persistentModelID)
        XCTAssertEqual(project.conversations.count, 1)
        
        // When - Delete dialog after relationship modification
        try queryManager.delete(dialog)
        
        // Then - Project should exist with empty dialogs array
        let updatedProject = try testEnv.projects().first { $0.persistentModelID == project.persistentModelID }
        XCTAssertNotNil(updatedProject)
        XCTAssertEqual(updatedProject?.conversations.count, 0)
    }
    
    func testBulkDeletionPerformance() throws {
        // Skip during normal test runs unless performance profiling is needed
        continueAfterFailure = false
        
        // Given - Create large number of objects
        let count = 50 // Adjust based on test environment capabilities
        var dialogs: [ConversationItem] = []
        
        measure {
            // Setup - Create many dialogs
            dialogs = (1...count).map { testEnv.createConversation(title: "Dialog \($0)") }
            
            do {
                // When - Bulk delete
                try queryManager.deleteItems(dialogs)
                
                // Then - Verify all deleted
                XCTAssertEqual(try testEnv.conversations().count, 0)
            } catch {
                XCTFail("Bulk deletion failed: \(error)")
            }
        }
    }
    
    // MARK: - Complex Relationship Tests
    
    func testDeleteDialogWithBookmarks() throws {
        // Given - Create dialog with bookmarks
        let dialog = testEnv.createConversation(title: "Bookmarked Dialog")
        try queryManager.insert(dialog)
        
        // Create a message and bookmark
        let messageItem = MessageItem(role: "user", text: "Test content")
        let turn = ConversationTurn(sequenceNumber: 0, userMessage: messageItem, conversation: dialog)
        dialog.turns.append(turn)
        try queryManager.insert(dialog)
        let bookmark = BookmarkItem("Test Bookmark", turn: turn)
        try queryManager.insert(bookmark)
        
        // Verify initial state
        XCTAssertEqual(try testEnv.conversations().count, 1)
        XCTAssertEqual(try testEnv.bookmarks().count, 1)
        
        // When - Delete the dialog
        try queryManager.deleteItemPermanently(dialog)
        
        // Then - Both dialog and bookmarks should be deleted
        XCTAssertEqual(try testEnv.conversations().count, 0, "Dialog should be deleted")
        XCTAssertEqual(try testEnv.bookmarks().count, 0, "Associated bookmarks should be deleted")
    }
    
    func testDeleteMessageReferencedByBookmark() throws {
        // This test simulates the issue where views might hold references
        // to deleted objects by using bookmarks as a proxy
        
        // Given - Create dialog with a message and bookmark
        let dialog = testEnv.createConversation(title: "Dialog with Bookmarked Message")
        try queryManager.insert(dialog)
        
        // Create turn with message
        let messageItem = MessageItem(role: "user", text: "Test content")
        let turn = ConversationTurn(sequenceNumber: 1, userMessage: messageItem, conversation: dialog)
        dialog.turns.append(turn)
        try testEnv.save()
        
        // Create bookmark to the message
        let bookmark = BookmarkItem("Test Bookmark", turn: turn)
        try queryManager.insert(bookmark)
        
        // Verify initial state
        XCTAssertEqual(try testEnv.bookmarks().count, 1)
        
        // When - Delete the turn containing the message (simulates modifying conversation)
        dialog.turns.removeAll { $0.persistentModelID == turn.persistentModelID }
        try testEnv.save()
        
        // Then - Bookmark should have invalid message reference but still exist
        // Note: This test documents current behavior, not necessarily ideal behavior
        let bookmarks = try testEnv.bookmarks()
        XCTAssertEqual(bookmarks.count, 1, "Bookmark still exists after referenced message is deleted")
        
        // Validate the bookmark still exists, which is the important part of the test
        let bookmarkAfterDeletion = bookmarks.first
        XCTAssertNotNil(bookmarkAfterDeletion, "Bookmark should still exist after referenced message deletion")
    }
}
