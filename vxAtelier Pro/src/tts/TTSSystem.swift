import AVFoundation
import SwiftUI
import SwiftData
import NaturalLanguage

// MARK: - Types & Models

/// Represents a segment of text with its detected language.
/// Used for breaking down multi-language messages into speakable parts.
///
/// Requirements:
/// - Text must not be empty
/// - Language code must be a valid ISO language code (e.g., "en", "de", "fr")
/// - Language code may include region (e.g., "en-US", "de-CH") but only base language is used for matching
///
/// Assumptions:
/// - Text is properly sanitized and trimmed
/// - Language detection has been performed on the text
struct TTSSegment {
    /// The actual text content to be spoken
    /// Must be non-empty and properly sanitized
    let text: String
    
    /// The detected language code (e.g., "en", "de", "fr")
    /// May include region code (e.g., "en-US", "de-CH") but only base language is used for matching
    let language: String
}

/// Represents the repeat mode for TTS playback.
/// Controls how the system handles playback completion.
///
/// Usage:
/// - none: Stop after playing the last item
/// - one: Continuously repeat the current item
/// - all: Repeat the entire playlist when reaching the end
enum TTSRepeatMode: String {
    case none    // Stop at end
    case one     // Repeat current item
    case all     // Repeat entire playlist
}

/// Represents the context of a message being played.
/// Provides metadata and display information for the current playback item.
///
/// Requirements:
/// - MessageItem must be valid and contain text content
/// - Dialog title must not be empty
/// - Message index must be non-negative
///
/// Dependencies:
/// - Requires MessageItem model from the data layer
/// - Integrates with the project/dialog hierarchy system
struct MessageContext {
    // MARK: Properties
    
    /// The message content and metadata
    /// Must be a valid MessageItem with non-empty content
    let message: MessageItem
    
    /// The title of the dialog this message belongs to
    /// Must not be empty
    let dialogTitle: String
    
    /// Optional project name if the message is part of a project
    /// Can be nil for standalone dialogs
    let projectName: String?
    
    /// The index of this message in its dialog
    /// Must be non-negative
    let messageIndex: Int
    
    // MARK: Computed Properties
    
    /// Formatted string for display in the UI
    /// Format: "[Project >] Dialog #Index"
    var displayString: String {
        if let project = projectName {
            return "\(project) › \(dialogTitle) #\(messageIndex + 1)"
        }
        return "\(dialogTitle) #\(messageIndex + 1)"
    }
}

// MARK: - TTSQueue Implementation

/// Manages text-to-speech functionality for the application.
/// Handles voice selection, playback control, and playlist management.
/// Supports multi-language text with automatic language detection and appropriate voice selection.
///
/// Dependencies:
/// - AVFoundation for speech synthesis
/// - NaturalLanguage for language detection
/// - SwiftUI for UI bindings
/// - SwiftData for data persistence
/// - ModelContext from SwiftUI environment for voice configurations
///
/// Requirements:
/// - iOS 13.0+ / macOS 10.15+
/// - Access to system voices
/// - Sufficient memory for text processing
/// - Must be used within a SwiftUI view hierarchy with ModelContext
///
/// Constraints:
/// - Language detection accuracy depends on text length
/// - Voice availability varies by system configuration
/// - Performance may degrade with very large playlists
/// - Memory usage increases with text size and playlist length
///
/// Thread Safety:
/// - All public methods are thread-safe
/// - UI updates are dispatched to the main thread
/// - Voice configuration is performed on initialization
@Observable final class TTSQueue: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    // MARK: Properties
    
    private let modelContext: ModelContext
    
    // MARK: Published State
    
    /// Whether speech synthesis is currently active
    var isPlaying: Bool = false
    /// Current position in the playlist
    var currentIndex: Int = 0
    /// Queue of messages to be spoken with their context
    var playlist: [(message: MessageItem, context: MessageContext)] = []
    
    // MARK: Private Properties
    
    /// The speech synthesizer instance
    private var synthesizer: AVSpeechSynthesizer!
    
    /// Flag to handle manual playlist navigation
    private var isManualSelection = false
    /// Current message segments for multi-language support
    private var currentSegments: [TTSSegment] = []
    /// Current position in the segments array
    private var currentSegmentIndex = 0
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        
        // Defer the synthesizer initialization until first use
        vxAtelierPro.log.debug("🔊 Basic system initialized")
    }
    
    /// Lazily initializes the speech synthesizer when needed
    private func getSynthesizer() -> AVSpeechSynthesizer {
        if synthesizer == nil {
            synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
            vxAtelierPro.log.debug("🔊 Speech synthesizer initialized")
        }
        return synthesizer
    }
    
    // MARK: - Voice Configuration
    
    /// Extracts the base language code from a language-region code.
    /// For example: "en-US" -> "en", "de-CH" -> "de"
    private func baseLanguageCode(_ languageCode: String) -> String {
        return languageCode.split(separator: "-").first.map(String.init) ?? languageCode
    }
    
    /// Gets the appropriate voice configuration for a role and language.
    /// Implements a fallback strategy for unavailable configurations.
    ///
    /// Selection Priority:
    /// 1. Exact match for role and language
    /// 2. Any configuration for the language
    /// 3. English configuration for the role
    /// 4. System default English voice
    ///
    /// Dependencies:
    /// - Requires modelContext from environment for SwiftData queries
    ///
    /// - Parameters:
    ///   - role: The role (user/assistant/system)
    ///   - language: The target language code
    /// - Returns: The most appropriate voice configuration
    private func getVoiceConfiguration(for role: String, language: String) -> VoiceConfigurationItem? {
        do {
            let baseLanguage = baseLanguageCode(language)
            
            // Try to find exact match for role and language
            let descriptor = FetchDescriptor<VoiceConfigurationItem>()
            let configs = try modelContext.fetch(descriptor)
            
            // First try exact match
            if let config = configs.first(where: { config in
                config.role == role && baseLanguageCode(config.language) == baseLanguage
            }) {
                vxAtelierPro.log.debug("🎤 Found exact voice configuration for role '\(role)' and language '\(language)'")
                return config
            }
            
            // Then try any configuration for this language
            if let config = configs.first(where: { config in
                baseLanguageCode(config.language) == baseLanguage
            }) {
                vxAtelierPro.log.debug("🎤 Using alternative voice configuration for language '\(language)'")
                return config
            }
            
            // Finally try English configuration for this role
            if let config = configs.first(where: { config in
                config.role == role && baseLanguageCode(config.language) == "en"
            }) {
                vxAtelierPro.log.debug("🎤 Falling back to English voice configuration for role '\(role)'")
                return config
            }
            
            vxAtelierPro.log.warning("⚠️ No voice configuration found for role '\(role)' and language '\(language)'")
            return nil
            
        } catch {
            vxAtelierPro.log.error("❌ Failed to fetch voice configurations - \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Gets the appropriate voice for a text segment based on language and role.
    /// Uses voice configurations when available, falls back to system defaults.
    ///
    /// Selection Priority:
    /// 1. Custom voice from configuration
    /// 2. System default voice for the language
    /// 3. English voice as fallback
    ///
    /// - Parameters:
    ///   - segment: The text segment with its detected language
    ///   - role: The role (user/assistant/system) for voice selection
    /// - Returns: The most appropriate voice for the segment
    private func getVoiceForSegment(_ segment: TTSSegment, role: String) -> (voice: AVSpeechSynthesisVoice, config: VoiceConfigurationItem?) {
        // Try to get voice from configuration
        if let config = getVoiceConfiguration(for: role, language: segment.language),
           !config.voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: config.voiceIdentifier) {
            vxAtelierPro.log.debug("🎤 Using configured voice '\(voice.name)' for role '\(role)' and language '\(segment.language)'")
            return (voice, config)
        }
        
        // If we have a config but no specific voice, use system default with the config's rate/pitch
        if let config = getVoiceConfiguration(for: role, language: segment.language),
           let defaultVoice = AVSpeechSynthesisVoice(language: segment.language) {
            vxAtelierPro.log.debug("🎤 Using system default voice with custom settings for language '\(segment.language)'")
            return (defaultVoice, config)
        }
        
        // Otherwise use system default voice for the language with default settings
        if let defaultVoice = AVSpeechSynthesisVoice(language: segment.language) {
            vxAtelierPro.log.debug("🎤 Using system default voice for language '\(segment.language)'")
            return (defaultVoice, nil)
        }
        
        // If no voice available for this language, fall back to English
        guard let englishVoice = AVSpeechSynthesisVoice(language: "en") else {
            vxAtelierPro.log.error("❌ Critical - No English fallback voice available")
            // Return any available voice as last resort
            return (AVSpeechSynthesisVoice.speechVoices().first ?? 
                AVSpeechSynthesisVoice(language: "en-US")!, nil) // This should never fail
        }
        return (englishVoice, nil)
    }
    
    // MARK: - Language Detection & Segmentation
    
    /// Detects the language of a given text segment using Natural Language processing.
    ///
    /// Requirements:
    /// - Text should be non-empty and meaningful
    /// - Text should be long enough for accurate detection (ideally > 10 characters)
    ///
    /// Behavior:
    /// - Returns raw language code from NLLanguageRecognizer
    /// - May return language code with region (e.g., "en-US", "de-CH")
    /// - Base language code is used for voice matching
    ///
    /// Constraints:
    /// - Detection accuracy varies with text length
    /// - Performance impact increases with text length
    /// - Memory usage proportional to text size
    ///
    /// - Parameter text: The text to analyze
    /// - Returns: The detected language code, defaults to "en" if detection fails
    private func detectLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage?.rawValue {
            return language
        }
        vxAtelierPro.log.warning("⚠️ Language detection failed for text, falling back to English")
        return "en"
    }
    
    /// Splits text into segments and detects their languages.
    /// Uses character-based separation with smart merging for short segments.
    ///
    /// Requirements:
    /// - Input text must be non-empty
    /// - Text should contain proper punctuation for optimal segmentation
    ///
    /// Behavior:
    /// - Splits text using sentence endings (.!?\n\r\t)
    /// - Further splits using soft separators (,:;-)
    /// - Merges short segments (<15 chars) with matching languages
    /// - Removes quotes and trims whitespace from segments
    /// - Filters out empty segments
    ///
    /// Constraints:
    /// - Short segments (<15 chars) may be merged if languages match
    /// - Performance depends on text length and segment count
    /// - Memory usage increases with number of segments
    ///
    /// - Parameter text: The text to segment
    /// - Returns: Array of TTSSegments with detected languages
    private func segmentText(_ text: String) -> [TTSSegment] {
        // Define separators for different cases
        let sentenceEndings = ".!?\n\r\t"
        let softSeparators = ",:;-"
        let quoteMarks = "\"'"
          
        // First split by separators
        let components = text.components(separatedBy: CharacterSet(charactersIn: sentenceEndings))
            .flatMap { sentence -> [String] in
                // Further split by soft separators if needed
                sentence.components(separatedBy: CharacterSet(charactersIn: softSeparators))
            }
            .map { segment -> String in
                // Clean up the segment
                var cleaned = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove any leading/trailing quotes
                cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: quoteMarks))
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        
        // Convert to TTSSegments with language detection
        var segments: [TTSSegment] = []
        var currentLanguage: String?
        var currentText = ""
        
        for component in components {
            let language = detectLanguage(for: component)
            
            // If this is a short component (< 15 chars) and we have a current language
            if component.count < 15, let current = currentLanguage {
                // Only merge if languages match
                if language == current {
                    if !currentText.isEmpty {
                        currentText += ", "
                    }
                    currentText += component
                    continue
                }
            }
            
            // Save accumulated text if any
            if !currentText.isEmpty {
                segments.append(TTSSegment(text: currentText, language: currentLanguage!))
            }
            
            // Start new segment
            currentText = component
            currentLanguage = language
        }
        
        // Add final segment if exists
        if !currentText.isEmpty {
            segments.append(TTSSegment(text: currentText, language: currentLanguage!))
        }
        
        return segments
    }
    
    // MARK: - Voice Selection
    
    /// Starts speaking a message, handling multi-language segmentation.
    /// Manages the lifecycle of speech synthesis for a message.
    ///
    /// Requirements:
    /// - Valid message with non-empty content
    /// - Properly initialized synthesizer
    ///
    /// Constraints:
    /// - One message spoken at a time
    /// - Memory usage proportional to message size
    /// - Processing time increases with segment count
    ///
    /// Side Effects:
    /// - Updates currentSegments
    /// - Updates currentSegmentIndex
    /// - Triggers speech synthesis
    ///
    /// - Parameter message: The message to speak
    private func startSpeaking(_ message: MessageItem) {
        // Segment the text and store for sequential playback
        currentSegments = segmentText(message.content.text)
        currentSegmentIndex = 0
        
        guard !currentSegments.isEmpty else { return }
        
        speakNextSegment(role: message.role)
        
        vxAtelierPro.log.debug("🗣️ Speaking \(message.role) message with \(self.currentSegments.count) segments")
    }
    
    /// Speaks the next segment in the current message.
    ///
    /// Uses voice configuration settings:
    /// - Speech rate from voice configuration
    /// - Pitch multiplier from voice configuration
    /// - Falls back to defaults if no configuration exists
    ///
    /// - Parameter role: The role to use for voice selection
    private func speakNextSegment(role: String) {
        guard currentSegmentIndex < currentSegments.count else {
            currentSegments = []
            currentSegmentIndex = 0
            return
        }
        
        let segment = currentSegments[currentSegmentIndex]
        let utterance = AVSpeechUtterance(string: segment.text)
        
        // Get voice and its configuration settings
        let (voice, config) = getVoiceForSegment(segment, role: role)
        utterance.voice = voice
        
        // Apply speech rate and pitch from the configuration if available
        if let config = config {
            utterance.rate = Float(config.speechRate)
            utterance.pitchMultiplier = Float(config.pitchMultiplier)
            vxAtelierPro.log.debug("🎤 Using speech rate: \(config.speechRate), pitch: \(config.pitchMultiplier)")
        } else {
            // Use default values if no configuration is available
            utterance.rate = 0.5  // Default normal rate in AVSpeechUtterance
            utterance.pitchMultiplier = 1.0
            vxAtelierPro.log.debug("🎤 Using default speech rate: 0.5, pitch: 1.0")
        }
        
        vxAtelierPro.log.debug("🗣️ Speaking segment \(self.currentSegmentIndex + 1)/\(self.currentSegments.count) in language '\(segment.language)'")
        getSynthesizer().speak(utterance)
    }
    
    // MARK: - Public Interface
    
    /// Adds a message to the playlist and optionally starts playback.
    ///
    /// Requirements:
    /// - Valid message with non-empty content
    /// - Valid dialog title
    /// - Non-negative message index
    ///
    /// Constraints:
    /// - No limit on playlist size (memory permitting)
    /// - Thread-safe operation
    ///
    /// Side Effects:
    /// - Updates playlist
    /// - May start playback if playlist was empty
    ///
    /// - Parameters:
    ///   - message: The message to add
    ///   - dialogTitle: Title of the dialog
    ///   - messageIndex: Index in the dialog
    ///   - projectName: Optional project name
    func add(_ message: MessageItem, dialogTitle: String, messageIndex: Int, projectName: String? = nil) {
        let messageContext = MessageContext(
            message: message,
            dialogTitle: dialogTitle,
            projectName: projectName,
            messageIndex: messageIndex
        )
        playlist.append((message: message, context: messageContext))
        
        if !isPlaying && playlist.count == 1 {
            play()
        }
    }
    
    /// The currently playing item in the playlist.
    ///
    /// Thread Safety:
    /// - Safe to access from any thread
    /// - Updates are atomic
    ///
    /// Returns nil if:
    /// - Playlist is empty
    /// - Current index is invalid
    var currentItem: (message: MessageItem, context: MessageContext)? {
        guard !playlist.isEmpty, currentIndex < playlist.count else { return nil }
        return playlist[currentIndex]
    }
    
    /// Clears the playlist and stops playback.
    ///
    /// Side Effects:
    /// - Stops current playback immediately
    /// - Clears the playlist array
    /// - Resets current index to 0
    /// - Sets isPlaying to false
    ///
    /// Thread Safety:
    /// - Safe to call from any thread
    /// - Playlist modifications are atomic
    func clear() {
        stop()
        playlist.removeAll()
        currentIndex = 0
        currentSegments = []
        currentSegmentIndex = 0
    }
    
    /// Starts or resumes playback from the current position.
    ///
    /// Behavior:
    /// - If playlist is empty, does nothing
    /// - If at invalid index, attempts to start from beginning
    /// - If valid current item exists, starts speaking it
    ///
    /// Side Effects:
    /// - May update currentIndex
    /// - Triggers speech synthesis
    /// - Updates isPlaying state
    ///
    /// Dependencies:
    /// - Requires modelContext from environment for voice configuration
    func play() {
        guard let current = currentItem else { 
            if !playlist.isEmpty {
                currentIndex = 0
                if let current = currentItem {
                    startSpeaking(current.message)
                }
            }
            return 
        }
        
        startSpeaking(current.message)
    }
    
    /// Jumps to a specific item in the playlist and starts playback.
    ///
    /// Requirements:
    /// - Index must be within valid playlist bounds
    ///
    /// Side Effects:
    /// - Stops current playback if active
    /// - Updates currentIndex
    /// - Sets isManualSelection flag
    /// - Starts playback of new item
    ///
    /// - Parameter index: The target index in the playlist
    func jumpTo(_ index: Int) {
        jumpTo(index, manualSelection: true)
    }

    /// Jumps to a specific item with control over manual selection flag.
    /// - Parameters:
    ///   - index: The target index in the playlist
    ///   - manualSelection: Whether to treat as manual selection (suppresses autoplay chaining on completion)
    func jumpTo(_ index: Int, manualSelection: Bool) {
        guard index >= 0 && index < playlist.count else {
            vxAtelierPro.log.error("❌ Invalid jump index \(index)")
            return
        }
        
        isManualSelection = manualSelection
        
        if getSynthesizer().isSpeaking {
            getSynthesizer().stopSpeaking(at: .immediate)
        }
        
        currentIndex = index
        startSpeaking(playlist[index].message)
    }
    
    /// Pauses the current playback.
    ///
    /// Side Effects:
    /// - Pauses speech synthesis
    /// - Updates isPlaying state
    ///
    /// Thread Safety:
    /// - Safe to call from any thread
    /// - State updates are atomic
    func pause() {
        getSynthesizer().pauseSpeaking(at: .immediate)
        isPlaying = false
        vxAtelierPro.log.debug("⏸️ Playback paused")
    }
    
    /// Resumes playback from a paused state or starts new playback.
    ///
    /// Behavior:
    /// - If paused, continues from pause point
    /// - If not paused, starts new playback
    /// - If already playing, does nothing
    ///
    /// Side Effects:
    /// - May update isPlaying state
    /// - May trigger speech synthesis
    func resume() {
        if !isPlaying {
            if getSynthesizer().isPaused {
                getSynthesizer().continueSpeaking()
                isPlaying = true
                vxAtelierPro.log.debug("▶️ Playback resumed from pause")
            } else {
                vxAtelierPro.log.debug("▶️ Starting new playback")
                play()
            }
        }
    }
    
    /// Stops playback immediately.
    ///
    /// Side Effects:
    /// - Stops speech synthesis
    /// - Does not affect playlist or current index
    ///
    /// Thread Safety:
    /// - Safe to call from any thread
    /// - Operation is immediate
    func stop() {
        getSynthesizer().stopSpeaking(at: .immediate)
        isPlaying = false
        vxAtelierPro.log.debug("⏹️ Playback stopped")
    }
    
    /// Moves to the next item in the playlist.
    ///
    /// Behavior:
    /// - If at end of playlist, does nothing
    /// - Otherwise moves to next item and starts playback
    ///
    /// Side Effects:
    /// - May update currentIndex
    /// - May trigger playback
    func next() {
        guard !self.playlist.isEmpty else {
            vxAtelierPro.log.debug("⏭️ Cannot move to next - playlist is empty")
            return
        }
        if self.currentIndex < self.playlist.count - 1 {
            vxAtelierPro.log.debug("⏭️ Moving to next item (\(self.currentIndex + 2)/\(self.playlist.count))")
            jumpTo(self.currentIndex + 1, manualSelection: false)
        } else {
            let repeatMode = UserDefaults.standard.string(forKey: "TTSRepeatMode") ?? AppDefaults.ttsRepeatMode
            if repeatMode == "all" {
                vxAtelierPro.log.debug("🔄 Wrapping to start (repeat all mode)")
                jumpTo(0, manualSelection: false)
            } else {
                vxAtelierPro.log.debug("⏭️ Cannot move to next - already at end of \(self.playlist.count)")
            }
        }
    }
    
    /// Moves to the previous item in the playlist.
    ///
    /// Behavior:
    /// - If at start of playlist, does nothing
    /// - Otherwise moves to previous item and starts playback
    ///
    /// Side Effects:
    /// - May update currentIndex
    /// - May trigger playback
    func previous() {
        guard !playlist.isEmpty else {
            vxAtelierPro.log.debug("⏮️ Cannot move to previous - playlist is empty")
            return
        }
        if currentIndex > 0 {
            vxAtelierPro.log.debug("⏮️ Moving to previous item (\(self.currentIndex)/\(self.playlist.count))")
            jumpTo(self.currentIndex - 1, manualSelection: false)
        } else {
            let repeatMode = UserDefaults.standard.string(forKey: "TTSRepeatMode") ?? AppDefaults.ttsRepeatMode
            if repeatMode == "all" {
                vxAtelierPro.log.debug("🔁 Wrapping to end (repeat all mode)")
                jumpTo(self.playlist.count - 1, manualSelection: false)
            } else {
                vxAtelierPro.log.debug("⏮️ Cannot move to previous - already at start of playlist")
            }
        }
    }
    
    /// Removes an item from the playlist at the specified index.
    ///
    /// Behavior:
    /// - If index is invalid, does nothing
    /// - If removing current item, stops playback and moves to next item
    /// - If removing last item, updates currentIndex if needed
    ///
    /// Side Effects:
    /// - Updates playlist
    /// - May update currentIndex
    /// - May stop or trigger playback
    ///
    /// - Parameter index: The index of the item to remove
    func remove(at index: Int) {
        guard index >= 0 && index < playlist.count else {
            vxAtelierPro.log.error("❌ Invalid remove index \(index)")
            return
        }
        
        let wasPlaying = isPlaying
        
        // If removing currently playing item
        if index == currentIndex {
            stop()
            playlist.remove(at: index)
            
            // If there are more items after this one, play the next item
            if index < playlist.count {
                if wasPlaying {
                    startSpeaking(playlist[index].message)
                }
            } else if !playlist.isEmpty {
                // If we removed the last item but playlist isn't empty,
                // move currentIndex to last item
                currentIndex = playlist.count - 1
            }
        } else {
            playlist.remove(at: index)
            // If we removed an item before the current one, adjust currentIndex
            if index < currentIndex {
                currentIndex -= 1
            }
        }
        
        vxAtelierPro.log.debug("🗑️ Removed item at index \(index), playlist now has \(self.playlist.count) items")
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    /// Handles the start of an utterance.
    ///
    /// Thread Safety:
    /// - Called on background thread
    /// - All UI updates dispatched to main thread
    ///
    /// Side Effects:
    /// - Updates isPlaying state
    /// - Logs playback progress
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [self] in
            self.isPlaying = true
            if self.currentSegments.count > 1 {
                vxAtelierPro.log.debug("▶️ Started speaking segment \(self.currentSegmentIndex + 1)/\(self.currentSegments.count) of message \(self.currentIndex + 1)/\(self.playlist.count)")
            } else {
                vxAtelierPro.log.debug("▶️ Started speaking message \(self.currentIndex + 1)/\(self.playlist.count)")
            }
        }
    }
    
    /// Handles the completion of an utterance.
    ///
    /// Behavior:
    /// - Handles multi-segment message continuation
    /// - Manages playlist progression based on repeat mode
    /// - Handles manual selection completion
    ///
    /// Environment Dependencies:
    /// - Uses repeatMode setting from UserDefaults
    /// - Uses autoplay setting from UserDefaults
    ///
    /// Thread Safety:
    /// - Called on background thread
    /// - All UI updates dispatched to main thread
    ///
    /// Side Effects:
    /// - May update currentSegmentIndex
    /// - May update currentIndex
    /// - May update isPlaying state
    /// - May trigger next playback
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [self] in
            if !self.currentSegments.isEmpty && self.currentSegmentIndex < self.currentSegments.count - 1 {
                self.currentSegmentIndex += 1
                if let current = self.currentItem {
                    if self.currentSegments.count > 1 {
                        vxAtelierPro.log.debug("➡️ Moving to next segment (\(self.currentSegmentIndex + 1)/\(self.currentSegments.count))")
                    }
                    self.speakNextSegment(role: current.message.role)
                }
                return
            }
            
            guard !self.playlist.isEmpty else { return }
            
            if self.isManualSelection {
                self.isManualSelection = false
                vxAtelierPro.log.debug("👆 Manual selection playback completed")
                return
            }
            
            let repeatMode = UserDefaults.standard.string(forKey: "TTSRepeatMode") ?? AppDefaults.ttsRepeatMode
            let autoplay = UserDefaults.standard.bool(forKey: "TTSAutoplay")
            
            switch repeatMode {
            case "one":
                vxAtelierPro.log.debug("🔁 Repeating current message (\(self.currentIndex + 1)/\(self.playlist.count))")
                self.startSpeaking(self.playlist[self.currentIndex].message)
                
            case "all":
                if self.currentIndex < self.playlist.count - 1 {
                    self.currentIndex += 1
                    vxAtelierPro.log.debug("⏭️ Moving to next message (\(self.currentIndex + 1)/\(self.playlist.count))")
                    self.startSpeaking(self.playlist[self.currentIndex].message)
                } else if autoplay {
                    vxAtelierPro.log.debug("🔄 Reached end, restarting playlist (repeat all mode)")
                    self.currentIndex = 0
                    self.startSpeaking(self.playlist[0].message)
                } else {
                    vxAtelierPro.log.debug("✅ Playlist completed (repeat all mode, autoplay disabled)")
                    self.isPlaying = false
                }
                
            default: // "none"
                if self.currentIndex < self.playlist.count - 1 && autoplay {
                    self.currentIndex += 1
                    vxAtelierPro.log.debug("⏭️ Moving to next message (\(self.currentIndex + 1)/\(self.playlist.count))")
                    self.startSpeaking(self.playlist[self.currentIndex].message)
                } else {
                    vxAtelierPro.log.debug("✅ Playback completed (no repeat)")
                    self.isPlaying = false
                }
            }
        }
    }
} 
