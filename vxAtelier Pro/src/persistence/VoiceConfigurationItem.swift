import Foundation
import SwiftData
import SwiftUI
import AVFoundation

/// A model representing a voice configuration for text-to-speech synthesis.
///
/// This model manages the association between conversation roles (user, assistant, system)
/// and specific synthesized voices for different languages, enabling customized
/// voice feedback in multilingual conversations.
///
/// Key features:
/// - Language-specific voice mapping
/// - Role-based voice differentiation
/// - Customizable speech rate and pitch
/// - System voice integration
@Model
final class VoiceConfigurationItem {
    // MARK: - Types

    /// Represents the possible roles for voice configuration.
    ///
    /// Each role corresponds to a different participant in the conversation
    /// and can have a distinct voice assigned.
    enum Role: String, Codable {
        /// The human user in the conversation
        case user = "user"

        /// The AI assistant in the conversation
        case assistant = "assistant"

        /// System messages or notifications
        case system = "system"
    }

    // MARK: - Properties

    /// The language code for this configuration (e.g., "en-US", "ja-JP").
    ///
    /// Must be a valid ISO language code that AVSpeechSynthesis supports.
    var language: String

    /// The identifier for the specific voice to use.
    ///
    /// Set to empty string to use the system default voice for the language.
    var voiceIdentifier: String

    /// The role this configuration applies to (user, assistant, or system).
    ///
    /// Automatically validates and corrects invalid values to "user".
    var role: String {
        didSet {
            // Ensure role is always one of the valid values
            if !["user", "assistant", "system"].contains(role) {
                role = "user"
            }
        }
    }

    /// The speech rate for this voice, ranging from 0.3 (slower) to 0.9 (faster).
    ///
    /// Default is 0.5, which is normal speaking pace in AVSpeechUtterance.
    var speechRate: Double

    /// The pitch multiplier for this voice, ranging from 0.5 (lower) to 2.0 (higher).
    ///
    /// Default is 1.0, which is the normal pitch.
    var pitchMultiplier: Double

    // MARK: - Initialization

    /// Creates a new voice configuration with the specified settings.
    ///
    /// - Parameters:
    ///   - language: The ISO language code for this configuration
    ///   - voiceIdentifier: The specific voice identifier, or empty for system default
    ///   - role: The role this configuration applies to (defaults to "user")
    ///   - speechRate: The speech rate for this voice (default: 0.5, normal speed)
    ///   - pitchMultiplier: The pitch multiplier for this voice (default: 1.0)
    init(
        language: String,
        voiceIdentifier: String,
        role: String = "user",
        speechRate: Double = 0.5,
        pitchMultiplier: Double = 1.0
    ) {
        self.language = language
        self.voiceIdentifier = voiceIdentifier
        // Ensure role is always one of the valid values during initialization
        self.role = ["user", "assistant", "system"].contains(role) ? role : "user"
        self.speechRate = speechRate
        self.pitchMultiplier = pitchMultiplier
    }

    // MARK: - Factory Methods

    /// Creates a default voice configuration for a specified language.
    ///
    /// Attempts to find a system voice for the given language and creates
    /// a configuration with default settings using that voice.
    ///
    /// - Parameter language: The ISO language code to create a configuration for
    /// - Returns: A new configuration with default settings, or nil if no voice is available
    static func createDefault(for language: String) -> VoiceConfigurationItem? {
        guard let defaultVoice = AVSpeechSynthesisVoice(language: language) else { return nil }
        return VoiceConfigurationItem(
            language: language,
            voiceIdentifier: defaultVoice.identifier,
            role: "user",  // Default to user role
            speechRate: 0.5,
            pitchMultiplier: 1.0
        )
    }
} 