import XCTest
import SwiftData
@testable import vxAtelier_Pro_debug

@MainActor
final class PromptTemplateTests: XCTestCase {
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
        let template = PromptTemplate(name: "TestTemplate", summary: "Test summary", prompt: "Hello, {{name}}!", category: .User)
        context.insert(template)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<PromptTemplate>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "TestTemplate")
        XCTAssertEqual(fetched.first?.summary, "Test summary")
        XCTAssertEqual(fetched.first?.prompt, "Hello, {{name}}!")
        XCTAssertEqual(fetched.first?.category, .User)
        fetched.first?.category = .System
        try context.save()
        let updated = try context.fetch(FetchDescriptor<PromptTemplate>()).first
        XCTAssertEqual(updated?.category, .System)
        context.delete(updated!)
        try context.save()
        let empty = try context.fetch(FetchDescriptor<PromptTemplate>())
        XCTAssertTrue(empty.isEmpty)
    }

    func testEdgeCases() throws {
        let template = PromptTemplate(name: "", summary: "", prompt: "", category: .User)
        context.insert(template)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<PromptTemplate>()).first
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "")
    }
}
