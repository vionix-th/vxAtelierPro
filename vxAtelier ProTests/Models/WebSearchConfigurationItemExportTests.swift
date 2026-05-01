import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class WebSearchConfigurationItemExportTests: XCTestCase {
    func testExportImportRoundtrip() throws {
        let original = WebSearchConfigurationItem(name: "SearchConfig", provider: "Google", apiKey: "key", searchEngineId: "cx-123", isDefault: true, createdAt: Date())
        let exportData = WebSearchConfigurationExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(WebSearchConfigurationExportData.self, from: encoded)
        let restored = decoded.toDataItem()
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.provider, original.provider)
        XCTAssertEqual(restored.apiKey, original.apiKey)
        XCTAssertEqual(restored.searchEngineId, original.searchEngineId)
    }
}
