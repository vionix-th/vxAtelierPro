import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

final class PromptTemplateExportTests: XCTestCase {
    func testExportImportRoundtrip() throws {
        let original = PromptTemplate(name: "Greeting", summary: "Say hello", prompt: "Hello, {{name}}!", category: .User)
        let exportData = PromptTemplateExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(PromptTemplateExportData.self, from: encoded)
        let restored = decoded.toDataItem()
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.summary, original.summary)
        XCTAssertEqual(restored.prompt, original.prompt)
        XCTAssertEqual(restored.category, original.category)
    }
}
