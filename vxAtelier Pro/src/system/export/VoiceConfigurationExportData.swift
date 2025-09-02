import Foundation
import SwiftData

// MARK: - Voice Configuration Export

/// Serializable representation of a voice configuration for export/import.
/// Used to store speech settings for different roles and languages.
///
/// Properties:
/// - language: The ISO language code for this configuration
/// - voiceIdentifier: The specific voice identifier, or empty for system default
/// - role: The role this configuration applies to (user, assistant, system)
/// - speechRate: The speech rate (0.3-0.9, with 0.5 being normal speed)
/// - pitchMultiplier: The pitch multiplier (0.5-2.0, with 1.0 being normal pitch)
struct VoiceConfigurationExportData: Codable {
    let language: String
    let voiceIdentifier: String
    let role: String
    let speechRate: Double
    let pitchMultiplier: Double
    
    init(_ config: VoiceConfigurationItem) {
        self.language = config.language
        self.voiceIdentifier = config.voiceIdentifier
        self.role = config.role
        self.speechRate = config.speechRate
        self.pitchMultiplier = config.pitchMultiplier
    }
    
    func toDataItem() -> VoiceConfigurationItem {
        return VoiceConfigurationItem(
            language: language,
            voiceIdentifier: voiceIdentifier,
            role: role,
            speechRate: speechRate,
            pitchMultiplier: pitchMultiplier
        )
    }
} 