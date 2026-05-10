import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ModelItemTests: XCTestCase {
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
        let model = ModelItem(modelID: "gpt-4", contextSize: 8192)
        context.insert(model)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<ModelItem>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "gpt-4")
        fetched.first?.modelID = "gpt-4-32k"
        try context.save()
        let updated = try context.fetch(FetchDescriptor<ModelItem>()).first
        XCTAssertEqual(updated?.name, "gpt-4-32k")
        context.delete(updated!)
        try context.save()
        let empty = try context.fetch(FetchDescriptor<ModelItem>())
        XCTAssertTrue(empty.isEmpty)
    }

    func testModelMetadata() throws {
        let model = ModelItem(modelID: "gpt-4", contextSize: 8192)
        model.capabilitiesRaw = [LLMModelCapability.text.rawValue, LLMModelCapability.image.rawValue, LLMModelCapability.streaming.rawValue]
        context.insert(model)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<ModelItem>()).first
        XCTAssertEqual(Set(fetched?.capabilities ?? []), [.text, .image, .streaming])
    }

    func testConfigurationOwnership() throws {
        let config = APIConfigurationItem(
            name: "Scoped OpenAI",
            apiKey: "key",
            baseURL: "https://api.test.com/v1",
            providerID: .openAIPlatform
        )
        let model = ModelItem(modelID: "gpt-4", contextSize: 8192, apiConfiguration: config)
        context.insert(config)
        context.insert(model)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<ModelItem>()).first)
        XCTAssertEqual(fetched.apiConfiguration?.name, "Scoped OpenAI")
        XCTAssertEqual(fetched.apiConfiguration?.providerIDEnum, .openAIPlatform)
    }

    func testEdgeCases() throws {
        let model = ModelItem(modelID: "", contextSize: 0)
        context.insert(model)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<ModelItem>()).first
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "")
    }
}
