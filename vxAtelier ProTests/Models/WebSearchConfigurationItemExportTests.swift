import XCTest
import SwiftData
@testable import vxAtelier_Pro_debug

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
