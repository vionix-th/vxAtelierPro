import SwiftData
import XCTest
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class QueryManagerCommandTests: XCTestCase {
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

    func testLookupsReturnInsertedConversationAndProjectByIdentifier() throws {
        let project = try queryManager.createProject()
        let conversation = try queryManager.createConversation(in: project)

        XCTAssertEqual(queryManager.project(with: project.id)?.persistentModelID, project.persistentModelID)
        XCTAssertEqual(queryManager.conversation(with: conversation.id)?.persistentModelID, conversation.persistentModelID)
    }

    func testCreateConversationUsesDefaultAPIConfigurationWhenStandalone() throws {
        let config = APIConfigurationItem(
            name: "Default Config",
            baseURL: "https://api.example.com",
            isDefault: true,
            providerID: .openAIPlatform
        )
        try queryManager.insert(config)

        let conversation = try queryManager.createConversation()

        XCTAssertEqual(conversation.title, AppDefaults.newConversationName)
        XCTAssertEqual(conversation.options.apiConfiguration?.persistentModelID, config.persistentModelID)
        XCTAssertNil(conversation.project)
    }

    func testCreateConversationInProjectCopiesProjectDefaultOptions() throws {
        let config = APIConfigurationItem(
            name: "Scoped Config",
            baseURL: "https://api.example.com",
            isDefault: true,
            providerID: .openAIPlatform
        )
        let projectOptions = ConversationOptions(apiConfiguration: config)
        let project = ProjectItem("Scoped Project", defaultOptions: projectOptions)
        try queryManager.insert(config)
        try queryManager.insert(project)

        let conversation = try queryManager.createConversation(in: project)

        XCTAssertEqual(conversation.project?.persistentModelID, project.persistentModelID)
        XCTAssertFalse(conversation.options === project.defaultOptions)
        XCTAssertEqual(conversation.options.apiConfiguration?.persistentModelID, config.persistentModelID)
    }

    func testInsertAndDeleteItem() throws {
        let conversation = ConversationItem("Inserted Conversation")

        try queryManager.insert(conversation)
        XCTAssertEqual(try testEnv.conversations().map(\.persistentModelID), [conversation.persistentModelID])

        try queryManager.delete(conversation)
        XCTAssertTrue(try testEnv.conversations().isEmpty)
    }

    func testArchiveAndRestoreItem() throws {
        let conversation = try queryManager.createConversation()

        try queryManager.archiveItem(conversation)
        XCTAssertEqual(conversation.status, .archived)

        try queryManager.restoreItem(conversation)
        XCTAssertEqual(conversation.status, .active)
    }

    func testDeleteNonExistentItemDoesNotInsertObject() throws {
        let conversation = ConversationItem("Not in context")

        XCTAssertNoThrow(try queryManager.deleteItems([conversation]))
        XCTAssertFalse(try testEnv.conversations().contains { $0.title == "Not in context" })
    }

    func testArchiveNonModifiableItemThrows() throws {
        let conversation = try queryManager.createConversation()
        let message = MessageItem(role: "user", text: "Bookmarked")
        let turn = ConversationTurn(sequenceNumber: 0, userMessage: message, conversation: conversation)
        conversation.turns.append(turn)
        let bookmark = BookmarkItem("Bookmark", turn: turn)

        XCTAssertThrowsError(try queryManager.archiveItem(bookmark)) { error in
            XCTAssertTrue(error is AppError)
        }
    }

    func testDefaultApiConfigurationPrefersExplicitDefault() throws {
        let config1 = APIConfigurationItem(
            name: "Config 1",
            baseURL: "https://api.example.com",
            isDefault: false
        )
        let config2 = APIConfigurationItem(
            name: "Config 2",
            baseURL: "https://api2.example.com",
            isDefault: true
        )

        try queryManager.insert(config1)
        try queryManager.insert(config2)

        XCTAssertEqual(queryManager.defaultApiConfiguration?.name, "Config 2")

        config1.isDefault = true
        config2.isDefault = false
        try queryManager.saveContext()

        XCTAssertEqual(queryManager.defaultApiConfiguration?.name, "Config 1")
    }

    func testUpsertApiConfigurationNormalizesDefaultUniqueness() throws {
        let config1 = APIConfigurationItem(
            name: "Config 1",
            baseURL: "https://api.example.com",
            isDefault: true
        )
        let config2 = APIConfigurationItem(
            name: "Config 2",
            baseURL: "https://api2.example.com",
            isDefault: true
        )

        try queryManager.upsertAPIConfiguration(config1, makeDefault: true)
        try queryManager.upsertAPIConfiguration(config2, makeDefault: true)

        let configs = try testEnv.apiConfigurations()
        XCTAssertEqual(configs.filter(\.isDefault).count, 1)
        XCTAssertEqual(queryManager.defaultApiConfiguration?.persistentModelID, config2.persistentModelID)
    }

    func testUpsertApiConfigurationGuaranteesOneDefault() throws {
        let config1 = APIConfigurationItem(
            name: "Config 1",
            baseURL: "https://api.example.com",
            isDefault: false
        )
        let config2 = APIConfigurationItem(
            name: "Config 2",
            baseURL: "https://api2.example.com",
            isDefault: false
        )

        try queryManager.upsertAPIConfiguration(config1, makeDefault: false)
        try queryManager.upsertAPIConfiguration(config2, makeDefault: false)

        XCTAssertEqual(try testEnv.apiConfigurations().filter(\.isDefault).count, 1)
        XCTAssertNotNil(queryManager.defaultApiConfiguration)
    }

    func testUpsertWebSearchConfigurationNormalizesDefaultUniqueness() throws {
        let config1 = WebSearchConfigurationItem(name: "Search 1", isDefault: true)
        let config2 = WebSearchConfigurationItem(name: "Search 2", isDefault: true)

        try queryManager.upsertWebSearchConfiguration(config1, makeDefault: true)
        try queryManager.upsertWebSearchConfiguration(config2, makeDefault: true)

        let configs = try testEnv.fetchAll(WebSearchConfigurationItem.self)
        XCTAssertEqual(configs.filter(\.isDefault).count, 1)
        XCTAssertEqual(queryManager.defaultWebSearchConfiguration?.persistentModelID, config2.persistentModelID)
    }

    func testModelsForConfigurationReturnsOnlyScopedModels() throws {
        let configA = APIConfigurationItem(name: "A", baseURL: "https://a.example.com")
        let configB = APIConfigurationItem(name: "B", baseURL: "https://b.example.com")
        let descriptor = LLMModelDescriptor(
            id: "unit-model",
            providerID: .openAIPlatform,
            adapterIDs: [.openAIChatCompletions]
        )
        let modelA = ModelItem(descriptor: descriptor, apiConfiguration: configA)
        let modelB = ModelItem(descriptor: descriptor, apiConfiguration: configB)

        try queryManager.insert(configA)
        try queryManager.insert(configB)
        try queryManager.insert(modelA)
        try queryManager.insert(modelB)

        XCTAssertEqual(queryManager.models(for: configA).map(\.persistentModelID), [modelA.persistentModelID])
        XCTAssertEqual(queryManager.models(for: nil), [])
    }

    func testEnsureSystemConversationCreatesAndReusesSingleConversation() throws {
        let first = try XCTUnwrap(queryManager.ensureSystemConversation())
        let second = try XCTUnwrap(queryManager.ensureSystemConversation())

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
        XCTAssertEqual(first.purpose, .system)
        XCTAssertEqual(try testEnv.conversations().filter { $0.purpose == .system }.count, 1)
    }
}
