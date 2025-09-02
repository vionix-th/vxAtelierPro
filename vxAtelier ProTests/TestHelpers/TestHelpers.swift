import SwiftData
import XCTest
@testable import vxAtelier_Pro_debug

// MARK: - Test Helpers

/// A test environment for SwiftData tests that provides an in-memory ModelContainer.
@MainActor
final class TestEnvironment {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    
    init() {
        let schema = Schema([
            ConversationItem.self,
            ProjectItem.self,
            ConversationOptions.self,
            ConversationTurn.self,
            MessageItem.self,
            ContentItem.self,
            BookmarkItem.self,
            APIConfigurationItem.self,
            PromptTemplate.self,
            VoiceConfigurationItem.self,
            ModelItem.self,
            WebSearchConfigurationItem.self
        ])
        
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = ModelContext(modelContainer)
            modelContext.autosaveEnabled = false
        } catch {
            fatalError("Failed to create test model container: \(error)")
        }
    }
    
    func createQueryManager() -> QueryManager {
        QueryManager(modelContext: modelContext)
    }
    
    func save() throws {
        try modelContext.save()
    }
}

// MARK: - Model Factories

extension TestEnvironment {
    @discardableResult
    func createConversation(
        title: String = "Test Conversation",
        status: ItemStatus = .active,
        purpose: ConversationItem.DialogPurpose = .user,
        project: ProjectItem? = nil,
        timestamp: Date = Date()
    ) -> ConversationItem {
        let options = ConversationOptions()
        let conversation = ConversationItem(
            timestamp: timestamp,
            title: title,
            options: options
        )
        conversation.status = status
        conversation.purpose = purpose
        conversation.project = project
        modelContext.insert(conversation)
        try? modelContext.save()
        return conversation
    }
    
    @discardableResult
    func createProject(
        name: String = "Test Project",
        status: ItemStatus = .active,
        defaultOptions: ConversationOptions? = nil
    ) -> ProjectItem {
        let options = defaultOptions ?? ConversationOptions()
        let project = ProjectItem(name, defaultOptions: options)
        project.status = status
        modelContext.insert(project)
        try? modelContext.save()
        return project
    }
}

// MARK: - Assertions

extension XCTestCase {
    func assertThrowsAsyncError<T: Sendable>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
