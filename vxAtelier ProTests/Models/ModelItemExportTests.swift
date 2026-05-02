import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class ModelItemExportTests: XCTestCase {
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

    func testExportImportRoundtrip() throws {
        let config = APIConfigurationItem(
            name: "OpenAI Key A",
            apiKey: "key",
            baseURL: "https://api.test.com/v1",
            providerID: .openAIPlatform
        )
        let original = ModelItem(name: "gpt-4", contextSize: 8192, provider: "OpenAI", apiConfiguration: config)
        original.capabilities = [.text, .vision]
        let exportData = ModelExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(ModelExportData.self, from: encoded)
        let restored = decoded.toDataItem(apiConfigurations: [config])
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.contextSize, original.contextSize)
        XCTAssertEqual(restored.provider, original.provider)
        XCTAssertEqual(Set(restored.capabilities), Set(original.capabilities))
        XCTAssertEqual(restored.apiConfiguration?.name, config.name)
        let restoredMaxTokens = restored.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        XCTAssertEqual(restoredMaxTokens?.wireKey, "max_tokens")
    }

    func testJsonSerializerImportModelResolvesAPIConfigurationOwnership() throws {
        let config = APIConfigurationItem(
            name: "Scoped OpenAI",
            apiKey: "key",
            baseURL: "https://api.test.com/v1",
            providerID: .openAIPlatform
        )
        context.insert(config)
        try context.save()

        let original = ModelItem(
            name: "gpt-4.1",
            contextSize: 128000,
            provider: "OpenAI",
            apiConfiguration: config
        )
        let data = try JsonSerializer.exportModel(original)
        let restored = try JsonSerializer.importModel(from: data, context: context)

        XCTAssertEqual(restored.apiConfiguration?.id, config.id)
        XCTAssertEqual(restored.providerID, LLMProviderID.openAIPlatform.rawValue)
    }
}
