import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class APIConfigurationItemExportTests: XCTestCase {
    func testExportImportRoundtrip() throws {
        let original = APIConfigurationItem(name: "TestAPI", apiKey: "key", baseURL: "https://api.test.com/v1", isDefault: true, defaultModel: "gpt-4")
        let exportData = APIConfigurationExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(APIConfigurationExportData.self, from: encoded)
        let restored = decoded.toDataItem()
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.apiKey, original.apiKey)
        XCTAssertEqual(restored.baseURL, original.baseURL)
        XCTAssertEqual(restored.isDefault, original.isDefault)
    }
}
