import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class APIConfigurationItemExportTests: XCTestCase {
    func testExportImportRoundtrip() throws {
        let original = APIConfigurationItem(
            name: "TestAPI",
            apiKey: "key",
            baseURL: "https://api.test.com/v1",
            isDefault: true,
            defaultModel: "gpt-4",
            providerID: .custom
        )
        original.adapterID = LLMAdapterID.openRouterChatCompletions.rawValue
        original.authKind = LLMAuthKind.bearerToken.rawValue
        original.decodedHeaders = ["X-Trace": "trace"]
        original.decodedOptions = ["request_timeout_seconds": "45"]
        let exportData = APIConfigurationExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(APIConfigurationExportData.self, from: encoded)
        let restored = try decoded.toDataItem()
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.apiKey, original.apiKey)
        XCTAssertEqual(restored.baseURL, original.baseURL)
        XCTAssertEqual(restored.isDefault, original.isDefault)
        XCTAssertEqual(restored.parsedProviderID, .custom)
        XCTAssertEqual(restored.parsedAdapterID, .openRouterChatCompletions)
        XCTAssertEqual(restored.parsedAuthKind, .bearerToken)
        XCTAssertEqual(restored.defaultModel, "gpt-4")
        XCTAssertEqual(restored.decodedHeaders, ["X-Trace": "trace"])
        XCTAssertEqual(restored.decodedOptions, ["request_timeout_seconds": "45"])
        XCTAssertNoThrow(try LLMProviderRegistry.shared.resolveRoute(
            adapterID: try restored.requireAdapterID(),
            providerID: try restored.requireProviderID(),
            modelID: restored.defaultModel,
            configuration: try restored.makeLLMProviderConfiguration()
        ))
    }

    func testImportRejectsUnknownAndUnsupportedRouteIdentity() throws {
        let original = APIConfigurationItem(
            name: "OpenAI",
            apiKey: "key",
            baseURL: "https://api.test.com/v1",
            providerID: .openAIPlatform
        )
        let export = APIConfigurationExportData(original)

        try assertInvalidImport(export, replacing: ["providerID": "future-provider"], contains: "future-provider")
        try assertInvalidImport(export, replacing: ["adapterID": "future-adapter"], contains: "future-adapter")
        try assertInvalidImport(export, replacing: ["authKind": "future-auth"], contains: "future-auth")
        try assertInvalidImport(
            export,
            replacing: ["adapterID": LLMAdapterID.anthropicMessages.rawValue],
            contains: "cannot use"
        )
    }

    private func assertInvalidImport(
        _ export: APIConfigurationExportData,
        replacing values: [String: Any],
        contains expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try JSONEncoder().encode(export)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            file: file,
            line: line
        )
        for (key, value) in values {
            json[key] = value
        }
        let mutatedData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(APIConfigurationExportData.self, from: mutatedData)

        XCTAssertThrowsError(try decoded.toDataItem(), file: file, line: line) { error in
            guard case .invalidConfiguration(let message) = error as? LLMProviderError else {
                return XCTFail("Expected invalidConfiguration, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(message.contains(expectedText), "Unexpected message: \(message)", file: file, line: line)
        }
    }
}
