import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class ModelItemExportTests: XCTestCase {
    func testExportImportRoundtrip() throws {
        let original = ModelItem(name: "gpt-4", contextSize: 8192, provider: "OpenAI")
        original.capabilities = [.text, .vision]
        let exportData = ModelExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(ModelExportData.self, from: encoded)
        let restored = decoded.toDataItem()
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.contextSize, original.contextSize)
        XCTAssertEqual(restored.provider, original.provider)
        XCTAssertEqual(Set(restored.capabilities), Set(original.capabilities))
        let restoredMaxTokens = restored.parameterMappings.first {
            $0.endpointFamilyEnum == .chatCompletions && $0.semanticParameterIDEnum == .maxOutputTokens
        }
        XCTAssertEqual(restoredMaxTokens?.wireKey, "max_tokens")
    }
}
