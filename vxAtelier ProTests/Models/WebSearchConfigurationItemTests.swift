import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class WebSearchConfigurationItemTests: XCTestCase {
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
        let config = WebSearchConfigurationItem(name: "TestSearch", provider: "Google", apiKey: "key", searchEngineId: "search-123", isDefault: true, createdAt: Date())
        context.insert(config)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<WebSearchConfigurationItem>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "TestSearch")
        XCTAssertEqual(fetched.first?.provider, "Google")
        XCTAssertEqual(fetched.first?.apiKey, "key")
        XCTAssertEqual(fetched.first?.searchEngineId, "search-123")
        fetched.first?.name = "UpdatedSearch"
        try context.save()
        let updated = try context.fetch(FetchDescriptor<WebSearchConfigurationItem>()).first
        XCTAssertEqual(updated?.name, "UpdatedSearch")
        context.delete(updated!)
        try context.save()
        let empty = try context.fetch(FetchDescriptor<WebSearchConfigurationItem>())
        XCTAssertTrue(empty.isEmpty)
    }

    func testEdgeCases() throws {
        let config = WebSearchConfigurationItem(name: "", provider: "", apiKey: nil, searchEngineId: nil, isDefault: false, createdAt: Date())
        context.insert(config)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<WebSearchConfigurationItem>()).first
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "")
    }
}
