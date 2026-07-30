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
        config.adapterID = LLMAdapterID.openAIChatCompletions.rawValue
        let original = ModelItem(modelID: "gpt-4", contextSize: 8192, apiConfiguration: config)
        original.providerSupportedCapabilitiesRaw = [
            LLMModelCapability.text.rawValue,
            LLMModelCapability.image.rawValue,
            LLMModelCapability.streaming.rawValue
        ]
        let exportData = ModelExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(ModelExportData.self, from: encoded)
        let restored = try decoded.toDataItem(apiConfigurations: [config])
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.contextSize, original.contextSize)
        XCTAssertEqual(Set(restored.providerSupportedCapabilitiesRaw), Set(original.providerSupportedCapabilitiesRaw))
        XCTAssertEqual(restored.apiConfiguration?.name, config.name)
        XCTAssertEqual(restored.apiConfiguration?.parsedAdapterID, .openAIChatCompletions)
        let restoredMaxTokens = restored.modelProfile.parameters[.maxOutputTokens]?.mapping
        XCTAssertEqual(restoredMaxTokens?.wireKey, "max_completion_tokens")
        XCTAssertEqual(restored.modelProfile.parameters[.maxOutputTokens]?.support.state, .supported)
        XCTAssertTrue(restored.parameterOverrides.isEmpty)
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
            modelID: "gpt-4.1",
            contextSize: 128000,
            apiConfiguration: config
        )
        let data = try JsonSerializer.exportModel(original)
        let restored = try JsonSerializer.importModel(from: data, context: context)

        XCTAssertEqual(restored.apiConfiguration?.id, config.id)
        XCTAssertEqual(restored.apiConfiguration?.parsedProviderID, .openAIPlatform)
    }

    func testBackupVersionFiveRoundTripsConfigurationAndModelRouteIdentity() throws {
        let configuration = APIConfigurationItem(
            name: "OpenRouter",
            apiKey: "key",
            baseURL: "https://openrouter.ai/api/v1",
            providerID: .openRouter
        )
        let model = ModelItem(
            modelID: "openai/gpt-5.4-nano",
            apiConfiguration: configuration
        )
        let backup = FullBackup(
            projects: [],
            conversations: [],
            bookmarks: [],
            promptTemplates: [],
            voiceConfigurations: [],
            ttsPlaylists: [],
            apiConfigurations: [APIConfigurationExportData(configuration)],
            models: [ModelExportData(model)],
            webSearchConfigurations: []
        )

        let data = try JSONEncoder().encode(backup)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 5)

        let decoded = try JSONDecoder().decode(FullBackup.self, from: data)
        let restoredConfiguration = try XCTUnwrap(decoded.apiConfigurations.first).toDataItem()
        let restoredModel = try XCTUnwrap(decoded.models.first).toDataItem(
            apiConfigurations: [restoredConfiguration]
        )
        XCTAssertEqual(restoredConfiguration.parsedProviderID, .openRouter)
        XCTAssertEqual(restoredConfiguration.parsedAdapterID, .openRouterChatCompletions)
        XCTAssertEqual(restoredModel.apiConfiguration?.parsedAdapterID, .openRouterChatCompletions)

        var versionFour = json
        versionFour["version"] = 4
        let versionFourData = try JSONSerialization.data(withJSONObject: versionFour)
        XCTAssertThrowsError(try JSONDecoder().decode(FullBackup.self, from: versionFourData))
    }
}
