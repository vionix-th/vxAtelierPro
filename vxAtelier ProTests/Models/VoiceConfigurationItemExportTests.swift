import XCTest
import SwiftData
@testable import vxAtelier_Pro_debug

final class VoiceConfigurationItemExportTests: XCTestCase {
    func testExportImportRoundtrip() throws {
        let original = VoiceConfigurationItem(language: "en-US", voiceIdentifier: "com.apple.ttsbundle.siri_female_en-US_compact", role: "assistant", speechRate: 0.5, pitchMultiplier: 1.0)
        let exportData = VoiceConfigurationExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(VoiceConfigurationExportData.self, from: encoded)
        let restored = decoded.toDataItem()
        XCTAssertEqual(restored.language, original.language)
        XCTAssertEqual(restored.voiceIdentifier, original.voiceIdentifier)
        XCTAssertEqual(restored.role, original.role)
        XCTAssertEqual(restored.speechRate, original.speechRate)
        XCTAssertEqual(restored.pitchMultiplier, original.pitchMultiplier)
    }
    
    func testExportHandlesInvalidRole() throws {
        let original = VoiceConfigurationItem(language: "en-US", voiceIdentifier: "id", role: "invalid", speechRate: 0.4, pitchMultiplier: 1.2)
        let exportData = VoiceConfigurationExportData(original)
        let encoded = try JSONEncoder().encode(exportData)
        let decoded = try JSONDecoder().decode(VoiceConfigurationExportData.self, from: encoded)
        let restored = decoded.toDataItem()
        // Model logic should correct role to 'user' if invalid
        XCTAssertEqual(restored.role, "user")
    }
}
