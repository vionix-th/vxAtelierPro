import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

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
            MessageContentPartItem.self,
            ToolCallItem.self,
            ResponseRunItem.self,
            BookmarkItem.self,
            APIConfigurationItem.self,
            PromptTemplate.self,
            VoiceConfigurationItem.self,
            ModelItem.self,
            ModelParameterMappingItem.self,
            ModelParameterAvailabilityItem.self,
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

    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }

    func conversations() throws -> [ConversationItem] {
        try fetchAll(ConversationItem.self)
            .sorted { $0.timestamp > $1.timestamp }
    }

    func projects() throws -> [ProjectItem] {
        try fetchAll(ProjectItem.self)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func bookmarks() throws -> [BookmarkItem] {
        try fetchAll(BookmarkItem.self)
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    func apiConfigurations() throws -> [APIConfigurationItem] {
        try fetchAll(APIConfigurationItem.self)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func standaloneConversations(
        showSystemConversations: Bool,
        contentFilter: ContentFilter
    ) throws -> [ConversationItem] {
        try conversations().filter { conversation in
            guard conversation.project == nil else { return false }
            switch contentFilter {
            case .active:
                guard conversation.status == .active else { return false }
            case .archived:
                guard conversation.status == .archived else { return false }
            case .trashed:
                guard conversation.status == .trashed else { return false }
            }
            if !showSystemConversations && conversation.purpose == .system {
                return false
            }
            return true
        }
    }
}

// MARK: - Model Factories

extension TestEnvironment {
    @discardableResult
    func createConversation(
        title: String = "Test Conversation",
        status: ItemStatus = .active,
        purpose: ConversationItem.ConversationPurpose = .user,
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

extension LLMRequest {
    static func runtimeEquivalent(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String,
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        options: LLMGenerationOptions = LLMGenerationOptions()
    ) -> LLMRequest {
        let candidate = LLMDefaultsCatalog.bundled.modelDescriptor(
            providerID: providerID,
            modelID: modelID
        )
        return LLMRequest(
            providerID: providerID,
            adapterID: adapterID,
            modelID: modelID,
            modelCapabilities: candidate.capabilities,
            parameterMappings: LLMParameterMappingCatalog.defaults(
                providerID: providerID,
                adapterID: adapterID,
                modelID: modelID
            ),
            parameterAvailability: LLMParameterAvailabilityCatalog.defaults(
                providerID: providerID,
                adapterID: adapterID,
                modelID: modelID
            ),
            messages: messages,
            tools: tools,
            options: options
        )
    }
}
