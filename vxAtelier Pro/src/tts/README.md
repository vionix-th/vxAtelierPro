---
description: Text-to-Speech (TTS) System with Voice Configuration Management
globs: src/tts/**, src/configuration/VoiceConfiguration*.swift
---
# Text-to-Speech System

A robust solution for managing and playing back text-to-speech with a user-friendly interface for configuring voices based on roles and languages.

## Core Components

### Voice Configuration

- **VoiceConfigurationItem**: SwiftData model for storing voice preferences
  - Manages role-based voice settings (user, assistant, system)
  - Supports language-specific voice configurations
  - Handles custom voice selection and system defaults
  - Smart language matching ignoring region codes (e.g., "en" matches "en-US")
  - Ensures uniqueness of role+language combinations

- **VoiceConfigurationListView**: UI for managing voice configurations
  - Add, edit, and delete voice configurations
  - Preview voices with live playback
  - Modern, spacious layout with clear sections
  - Immediate validation and error feedback

### Playback System

- **TTSQueue**: Core playback management
  - Uses SwiftData voice configurations for role-based voice selection
  - Supports multi-language text with automatic detection
  - Language matching ignores region codes for better provider matching
  - Smart fallback strategy for unavailable voices
  - Comprehensive logging for debugging
  - Thread-safe operations with main thread UI updates

- **TTSControlView**: Playback control interface
  - Transport controls (play/pause, next/previous)
  - Playlist management with visual feedback
  - Repeat mode and autoplay settings
  - Progress indication and navigation

## Features

### Voice Configuration
- Role-based voice assignment
- Language-specific configurations
- Region-independent language matching
- System default fallbacks
- Preview functionality
- Duplicate prevention
- Persistent storage

### Voice Selection
- Gender indicators (👨/👩)
- Quality indicators (✨ for enhanced voices)
- System default option
- Grouped by language
- Sorted by localized names

### Language Detection
- Automatic language detection for text segments
- Supports mixed-language content
- Region-independent matching (e.g., "de" matches "de-CH")
- Smart fallback to English when needed
- Configurable voice selection per language

### User Interface
- Modern SwiftUI design
- Clear visual hierarchy
- Intuitive controls
- Error handling
- Accessibility support

## Logging System

### Categories and Levels
```swift
// Debug: Routine operations
vxAtelierPro.log.debug("🎤 VoiceConfigurationView: Loading voices")

// Notice: Important changes
vxAtelierPro.log.notice("🎤 VoiceConfigurationView: Configuration saved")

// Warning: Potential issues
vxAtelierPro.log.warning("🎤 VoiceConfigurationView: Duplicate detected")

// Error: Operation failures
vxAtelierPro.log.error("🎤 VoiceConfigurationView: Preview failed")
```

### Log Format
- 🎤 Voice configuration events
- Component prefix for filtering
- Contextual information included
- Action-oriented messages

### Performance Considerations
- Avoid logging in render cycles
- Use appropriate log levels
- Include relevant context
- Maintain SwiftUI performance

## Requirements

- macOS 10.15+ / iOS 13.0+
- AVFoundation for speech synthesis
- SwiftData for configuration persistence
- NaturalLanguage for language detection

## Constraints

- Voice configurations must have unique role+language combinations
- Language detection accuracy depends on text length
- Voice availability varies by system configuration
- Performance may degrade with very large playlists
- Memory usage increases with text size and playlist length

## Usage

### Creating a Voice Configuration

```swift
// Create a new configuration
let config = VoiceConfigurationItem(
    language: "en-US",
    voiceIdentifier: "com.apple.voice.compact.en-US.Samantha",
    role: "assistant"
)

// Save to SwiftData
modelContext.insert(config)
```

### Previewing a Voice

```swift
// In VoiceConfigurationEditView
if let voice = selectedVoice {
    let utterance = AVSpeechUtterance(string: "Hello! This is a preview.")
    utterance.voice = voice
    synthesizer.speak(utterance)
}
```

## Best Practices

### Configuration Management

- Always validate role+language uniqueness
- Provide clear feedback for validation errors
- Use system default voices when custom voices unavailable
- Cache voice configurations for better performance

### User Interface

- Group settings logically (Basic Settings, Voice Selection)
- Provide immediate feedback for user actions
- Include voice preview functionality
- Use consistent spacing and visual hierarchy

### Logging

- Log all significant state changes
- Include context in log messages (role, language)
- Use appropriate log levels (debug, notice, warning, error)
- Add emojis for better log readability
- Avoid excessive logging in tight loops

## Future Improvements

- Support for voice quality preferences
- Batch configuration import/export
- Advanced voice mixing options
- Voice effect processing
- Integration with more TTS engines

## Version History

### 2.0.0 (Current)
- Migrated to SwiftData for voice configurations
- Improved voice selection UI
- Added comprehensive logging
- Enhanced error handling

### 1.0.0
- Initial release with AppStorage-based settings
- Basic voice selection
- Simple playback controls
