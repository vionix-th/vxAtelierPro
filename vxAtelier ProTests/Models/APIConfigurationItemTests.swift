import XCTest
import SwiftData
@testable import vxAtelier_Pro_debug

@MainActor
final class APIConfigurationItemTests: XCTestCase {
    private var testEnv: TestEnvironment!
    private var context: ModelContext! { testEnv.modelContext }

    override func setUp() {
        super.setUp()
        testEnv = TestEnvironment()
    }

    override func tearDown() {
        testEnv = nil
        super.tearDown()
    }

    func testCRUD() throws {
        let config = APIConfigurationItem(name: "TestAPI", apiKey: "key", baseURL: "https://api.test.com", chatCompletionsEndpoint: "/v1/chat", modelsEndpoint: "/v1/models", isDefault: true, defaultModel: "gpt-4")
        context.insert(config)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<APIConfigurationItem>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "TestAPI")
        fetched.first?.name = "UpdatedAPI"
        try context.save()
        let updated = try context.fetch(FetchDescriptor<APIConfigurationItem>()).first
        XCTAssertEqual(updated?.name, "UpdatedAPI")
        context.delete(updated!)
        try context.save()
        let empty = try context.fetch(FetchDescriptor<APIConfigurationItem>())
        XCTAssertTrue(empty.isEmpty)
    }

    func testRelationshipWithModelItem() throws {
        let config = APIConfigurationItem(name: "TestAPI", apiKey: "key", baseURL: "https://api.test.com", chatCompletionsEndpoint: "/v1/chat", modelsEndpoint: "/v1/models")
        let model = ModelItem(name: "gpt-4", contextSize: 8192, provider: "OpenAI")
        config.defaultModel = model.name
        context.insert(config)
        context.insert(model)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<APIConfigurationItem>()).first
        XCTAssertEqual(fetched?.defaultModel, "gpt-4")
    }

    func testEdgeCases() throws {
        let config = APIConfigurationItem(name: "", apiKey: "", baseURL: "", chatCompletionsEndpoint: "", modelsEndpoint: "")
        context.insert(config)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<APIConfigurationItem>()).first
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "")
    }
}
