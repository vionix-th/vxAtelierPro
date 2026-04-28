import XCTest
import SwiftData
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

@MainActor
final class VoiceConfigurationItemTests: XCTestCase {
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
        let voice = VoiceConfigurationItem(language: "en-US", voiceIdentifier: "com.apple.ttsbundle.siri_female_en-US_compact", role: "user", speechRate: 0.5, pitchMultiplier: 1.0)
        context.insert(voice)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<VoiceConfigurationItem>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.language, "en-US")
        XCTAssertEqual(fetched.first?.voiceIdentifier, "com.apple.ttsbundle.siri_female_en-US_compact")
        fetched.first?.speechRate = 0.7
        try context.save()
        let updated = try context.fetch(FetchDescriptor<VoiceConfigurationItem>()).first
        XCTAssertEqual(updated?.speechRate, 0.7)
        context.delete(updated!)
        try context.save()
        let empty = try context.fetch(FetchDescriptor<VoiceConfigurationItem>())
        XCTAssertTrue(empty.isEmpty)
    }

    func testEdgeCases() throws {
        let voice = VoiceConfigurationItem(language: "", voiceIdentifier: "", role: "invalid", speechRate: 0.3, pitchMultiplier: 0.5)
        context.insert(voice)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<VoiceConfigurationItem>()).first
        XCTAssertNotNil(fetched)
        // Role should be corrected to 'user' by model logic
        XCTAssertEqual(fetched?.role, "user")
    }
}
