import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ProjectItemTests: XCTestCase {
    private var testEnv: TestEnvironment!
    
    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }
    
    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        // Given
        let name = "Test Project"
        let options = ConversationOptions()
        let timestamp = Date()
        
        // When
        let project = ProjectItem(
            name,
            defaultOptions: options,
            status: .active,
            timestamp: timestamp
        )
        
        // Then
        XCTAssertEqual(project.name, name)
        XCTAssertTrue(project.conversations.isEmpty)
        XCTAssertEqual(project.status, .active)
        XCTAssertEqual(project.timestamp, timestamp)
        XCTAssertNotNil(project.defaultOptions)
    }
    
    // MARK: - Status Management Tests
    
    func testArchive() {
        // Given
        let project = testEnv.createProject()
        
        // When
        project.status = .archived
        
        // Then
        XCTAssertEqual(project.status, .archived)
    }
    
    func testTrash() {
        // Given
        let project = testEnv.createProject()
        
        // When
        project.status = .trashed
        
        // Then
        XCTAssertEqual(project.status, .trashed)
    }
    
    // MARK: - Persistence Tests
    
    func testPersistenceCRUD() throws {
        let context = testEnv.modelContext
        let project = ProjectItem("Persist Project", defaultOptions: ConversationOptions(), status: .active, timestamp: Date())
        context.insert(project)
        try context.save()
        let fetchProjects = try context.fetch(FetchDescriptor<ProjectItem>())
        XCTAssert(fetchProjects.contains { $0.name == "Persist Project" })
        project.name = "Updated Name"
        try context.save()
        let updated = try context.fetch(FetchDescriptor<ProjectItem>()).first { $0.name == "Updated Name" }
        XCTAssertNotNil(updated)
        context.delete(project)
        try context.save()
        let afterDelete = try context.fetch(FetchDescriptor<ProjectItem>())
        XCTAssertFalse(afterDelete.contains { $0.name == "Updated Name" })
    }

    // MARK: - Dialog Management Tests
    
    func testAddDialog() {
        // Given
        let project = testEnv.createProject()
        let dialog = testEnv.createConversation()
        
        // When
        project.conversations.append(dialog)
        
        // Then
        XCTAssertEqual(project.conversations.count, 1)
        XCTAssertEqual(project.conversations.first, dialog)
        XCTAssertEqual(dialog.project, project)
    }
    
    func testRemoveDialog() {
        // Given
        let project = testEnv.createProject()
        let dialog = testEnv.createConversation()
        project.conversations.append(dialog)
        
        // When
        project.conversations.removeAll()
        
        // Then
        XCTAssertTrue(project.conversations.isEmpty)
        XCTAssertNil(dialog.project)
    }

    func testCascadeDeleteRemovesDialogsAndOptions() throws {
        let context = testEnv.modelContext
        let project = ProjectItem("Cascade Project")
        let dialog = ConversationItem(timestamp: Date(), title: "Cascade Dialog", options: ConversationOptions())
        project.conversations.append(dialog)
        context.insert(project)
        try context.save()
        let dialogId = dialog.id
        let optionsId = project.defaultOptions.id
        context.delete(project)
        try context.save()
        let fetchDialogs = try context.fetch(FetchDescriptor<ConversationItem>())
        let fetchOptions = try context.fetch(FetchDescriptor<ConversationOptions>())
        XCTAssertFalse(fetchDialogs.contains { $0.id == dialogId })
        XCTAssertFalse(fetchOptions.contains { $0.id == optionsId })
    }

    func testDialogProjectNullifyOnRemove() {
        let project = testEnv.createProject()
        let dialog = testEnv.createConversation()
        project.conversations.append(dialog)
        project.conversations.removeAll(where: { $0 === dialog })
        XCTAssertNil(dialog.project)
    }

    func testInvalidProjectName() {
        let options = ConversationOptions()
        let project = ProjectItem("", defaultOptions: options)
        XCTAssertTrue(project.name.isEmpty)
        // Name validation is not enforced at model level, but should be at UI/service layer
    }

    func testDefaultOptionsInheritance() {
        let project = testEnv.createProject()
        let dialog = ConversationItem(timestamp: Date(), title: "WithDefaults", options: project.defaultOptions)
        project.conversations.append(dialog)
        XCTAssert(dialog.options === project.defaultOptions)
    }
    
    // MARK: - Sorted Dialogs Tests
    
    func testSortedConversations() {
        // Given
        let project = testEnv.createProject()
        let conversation1 = testEnv.createConversation()
        let conversation2 = testEnv.createConversation()
        
        // Set different timestamps
        conversation1.timestamp = Date().addingTimeInterval(-3600) // 1 hour ago
        conversation2.timestamp = Date() // now
        
        // Add to project
        project.conversations = [conversation1, conversation2]
        
        // When
        // Sort conversations by timestamp descending to mirror sortedConversations logic (SwiftData relationships are unordered)
        let sorted = project.sortedConversations
        
        // Then - should be sorted by timestamp descending
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0], conversation2) // Newest first
        XCTAssertEqual(sorted[1], conversation1)
    }
}
