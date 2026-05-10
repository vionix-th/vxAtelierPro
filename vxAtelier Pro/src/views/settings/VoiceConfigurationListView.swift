import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Voice Configuration List View

/// A view that displays and manages a list of voice configurations.
/// Provides functionality to add, edit, and delete voice configurations for different roles and languages.
///
/// Requirements:
/// - Must have access to a SwiftData model context
/// - Requires AVFoundation for voice synthesis capabilities
///
/// Constraints:
/// - Only one configuration allowed per language+role combination
/// - Configuration changes are persisted immediately
/// - Voice preview requires system audio permissions
struct VoiceConfigurationListView: View {
    // MARK: - Environment & State
    
    @Environment(\.modelContext) private var modelContext
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\VoiceConfigurationItem.language)]) private var voiceConfigurations: [VoiceConfigurationItem]
    
    @State private var editingConfig: EditingConfig?
    @State private var showError = false
    @State private var errorMessage = ""
    
    struct EditingConfig: Identifiable {
        let id = UUID()
        var config: VoiceConfigurationItem
        var isNew: Bool
    }
    
    // MARK: - View Body
    
    var body: some View {
        VStack(spacing: AppDefaults.paddingMedium) {
            if voiceConfigurations.isEmpty {
                ContentUnavailableView(
                    "No Voice Configurations",
                    systemImage: "waveform",
                    description: Text("Add a voice configuration to customize speech for different roles.")
                )
                .padding(.vertical, AppDefaults.paddingLarge)
                .onAppear {
                    vxAtelierPro.log.debug("🎤 No configurations available")
                }
            } else {
                VStack {
                    ForEach(voiceConfigurations) { config in
                        SettingsListRow(
                            title: config.role.capitalized,
                            subtitle: Locale.current.localizedString(forIdentifier: config.language) ?? config.language,
                            icons: config.voiceIdentifier.isEmpty ? [] : [Image(systemName: "waveform")],
                            onEdit: {
                                vxAtelierPro.log.debug("🎤 Editing configuration for role '\(config.role)' and language '\(config.language)'")
                                editingConfig = EditingConfig(config: config, isNew: false)
                            },
                            onDelete: {
                                vxAtelierPro.log.notice("🎤 Deleting configuration for role '\(config.role)' and language '\(config.language)'")
                                do {
                                    try queryManager.delete(config)
                                } catch {
                                    vxAtelierPro.log.error("🎤 Failed to delete configuration: \(error.localizedDescription)")
                                    errorMessage = "Failed to delete configuration: \(error.localizedDescription)"
                                    showError = true
                                }
                            }
                        ) {
                            if !config.voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: config.voiceIdentifier) {
                                Text(voice.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            
            Button {
                vxAtelierPro.log.debug("🎤 Creating new configuration")
                editingConfig = EditingConfig(config: VoiceConfigurationItem(
                    language: "en-US",
                    voiceIdentifier: "",
                    role: "user"
                ), isNew: true)
            } label: {
                Label("Add Configuration", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, AppDefaults.paddingMedium)
        }
        .sheet(item: $editingConfig) { editing in
            NavigationStack {
                VoiceConfigurationEditView(
                    configuration: editing.config,
                    isNewConfig: editing.isNew,
                    configurations: voiceConfigurations,
                    onComplete: { success in
                        if success {
                            do {
                                if editing.isNew {
                                    try queryManager.insert(editing.config)
                                    vxAtelierPro.log.notice("🎤 Added new configuration for role '\(editing.config.role)' and language '\(editing.config.language)'")
                                } else {
                                    try queryManager.saveContext()
                                    vxAtelierPro.log.notice("🎤 Updated configuration for role '\(editing.config.role)' and language '\(editing.config.language)'")
                                }
                            } catch {
                                vxAtelierPro.log.error("🎤 Failed to save configuration: \(error.localizedDescription)")
                                errorMessage = "Failed to save configuration: \(error.localizedDescription)"
                                showError = true
                            }
                        } else {
                            vxAtelierPro.log.debug("🎤 Configuration edit cancelled")
                        }
                        editingConfig = nil
                    }
                )
            }
        }
        .alert("Configuration Error", isPresented: $showError) {
            Button("OK") { 
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Private Views
    
    /// Creates a row view for a single voice configuration.
    /// Displays role, language, selected voice (if any), and action buttons.
    ///
    /// - Parameter config: The configuration item to display
    /// - Returns: A view representing the configuration
    private func configurationRow(_ config: VoiceConfigurationItem) -> some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                Text(config.role.capitalized)
                    .font(.headline)
                Text(Locale.current.localizedString(forIdentifier: config.language) ?? config.language)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Show voice info if custom voice is selected
            if !config.voiceIdentifier.isEmpty,
               let voice = AVSpeechSynthesisVoice(identifier: config.voiceIdentifier) {
                Text(voice.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack(spacing: AppDefaults.paddingMedium) {
                Button {
                    vxAtelierPro.log.debug("🎤 Editing configuration for role '\(config.role)' and language '\(config.language)'")
                    editingConfig = EditingConfig(config: config, isNew: false)
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                }
                
                Button {
                    vxAtelierPro.log.notice("🎤 Deleting configuration for role '\(config.role)' and language '\(config.language)'")
                    do {
                        try queryManager.delete(config)
                    } catch {
                        vxAtelierPro.log.error("🎤 Failed to delete configuration: \(error.localizedDescription)")
                        errorMessage = "Failed to delete configuration: \(error.localizedDescription)"
                        showError = true
                    }
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppDefaults.paddingLarge)
        .padding(.vertical, AppDefaults.paddingMedium)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
    }
}

// MARK: - Voice Configuration Edit View

/// A view for editing or creating a voice configuration.
/// Provides controls for selecting role, language, and voice, with live preview capabilities.
///
/// Requirements:
/// - Must be presented within a NavigationStack
/// - Requires access to AVSpeechSynthesis for voice preview
///
/// Constraints:
/// - Language+role combination must be unique
/// - Voice selection depends on system-available voices
/// - Preview functionality requires audio permissions
struct VoiceConfigurationEditView: View {
    // MARK: - Environment & Properties
    
    @Environment(\.dismiss) private var dismiss
    @Bindable var configuration: VoiceConfigurationItem
    let isNewConfig: Bool
    let configurations: [VoiceConfigurationItem]
    var onComplete: (Bool) -> Void
    
    // MARK: - State
    
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var voicesByLanguage: [String: [AVSpeechSynthesisVoice]] = [:]
    @State private var availableLanguages: [String] = []
    @State private var showError = false
    @State private var errorMessage = ""
    
    @State private var isPreviewPlaying = false
    private let synthesizer = AVSpeechSynthesizer()
    
    private let roles = ["user", "assistant", "system"]
    
    // Speech rate presets with descriptive names and actual AVSpeechUtterance rate values
    private let speechRatePresets: [(label: String, value: Double)] = [
        ("Very Slow", 0.05),
        ("Slower", 0.3),
        ("Normal", 0.5),  // This is normal speech in AVSpeechUtterance
        ("Faster", 0.6),
        ("Very Fast", 0.7)
    ]
    
    // Pitch control range
    private let pitchRange: ClosedRange<Double> = 0.5...2.0
    private let pitchStep: Double = 0.05
    
    // MARK: - View Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppDefaults.paddingLarge) {
                // Role and Language Section
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Basic Settings")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppDefaults.paddingLarge)
                    
                    VStack(spacing: AppDefaults.paddingMedium) {
                        // Role Picker
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Role")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Picker("", selection: $configuration.role) {
                                ForEach(roles, id: \.self) { role in
                                    Label(role.capitalized, systemImage: roleIcon(for: role))
                                        .tag(role)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Language Picker
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Language")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Picker("", selection: $configuration.language) {
                                ForEach(availableLanguages, id: \.self) { language in
                                    Text(Locale.current.localizedString(forIdentifier: language) ?? language)
                                        .tag(language)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .padding(AppDefaults.paddingLarge)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
                    .padding(.horizontal, AppDefaults.paddingLarge)
                }
                
                // Voice Selection Section
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Voice Selection")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppDefaults.paddingLarge)
                    
                    VStack(spacing: AppDefaults.paddingLarge) {
                        // Voice Picker
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Voice")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Picker("", selection: $configuration.voiceIdentifier) {
                                Text("System Default")
                                    .tag("")
                                ForEach(voicesByLanguage[configuration.language] ?? [], id: \.identifier) { voice in
                                    HStack {
                                        Image(systemName: voice.gender == .female ? "person.circle.fill" : "person.circle")
                                            .foregroundColor(voice.quality == .enhanced ? .accentColor : .secondary)
                                        Text(voice.name)
                                        if voice.quality == .enhanced {
                                            Image(systemName: "sparkles")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .tag(voice.identifier)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        // Speech Rate Section
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Speech Rate")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // Picker for speech rate with descriptive labels
                            Picker("Speech Rate", selection: $configuration.speechRate) {
                                ForEach(speechRatePresets, id: \.value) { preset in
                                    Text(preset.label).tag(preset.value)
                                }
                            }
                            // Use menu style for better handling of multiple options
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Pitch Section with Slider
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            HStack {
                                Text("Pitch")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(formatPitch(configuration.pitchMultiplier))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .foregroundColor(.secondary)
                                
                                Slider(
                                    value: $configuration.pitchMultiplier,
                                    in: pitchRange,
                                    step: pitchStep
                                )
                                
                                Image(systemName: "music.quarternote.3")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Preview Section
                        if let voice = selectedVoice {
                            VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Current Voice")
                                            .font(.headline)
                                        HStack {
                                            Image(systemName: voice.gender == .female ? "person.circle.fill" : "person.circle")
                                                .foregroundColor(voice.quality == .enhanced ? .accentColor : .secondary)
                                            Text(voice.name)
                                                .font(.subheadline)
                                            if voice.quality == .enhanced {
                                                Image(systemName: "sparkles")
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        
                                        Text("\(getSpeechRateLabel(configuration.speechRate)) speed, \(formatPitch(configuration.pitchMultiplier)) pitch")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        previewVoice()
                                    } label: {
                                        Label(isPreviewPlaying ? "Stop" : "Preview", systemImage: isPreviewPlaying ? "stop.circle.fill" : "play.circle.fill")
                                            .font(.headline)
                                            .foregroundColor(isPreviewPlaying ? .red : .accentColor)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(synthesizer.isSpeaking && !isPreviewPlaying)
                                }
                            }
                            .padding(AppDefaults.paddingLarge)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
                        }
                    }
                    .padding(AppDefaults.paddingLarge)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
                    .padding(.horizontal, AppDefaults.paddingLarge)
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge)
        }
        .navigationTitle("Edit Voice Configuration")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    vxAtelierPro.log.debug("🎤 VoiceConfigurationEditView: Edit cancelled")
                    onComplete(false)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    // Check for uniqueness of language+role combination
                    let existingConfig = configurations.first { item in
                        item.language == configuration.language && 
                        item.role == configuration.role &&
                        item.persistentModelID != configuration.persistentModelID
                    }
                    
                    if let _ = existingConfig {
                        vxAtelierPro.log.warning("🎤 VoiceConfigurationEditView: Duplicate configuration attempted for role '\(configuration.role)' and language '\(configuration.language)'")
                        errorMessage = "A voice configuration for '\(configuration.role)' with language '\(configuration.language)' already exists."
                        showError = true
                        return
                    }
                    
                    vxAtelierPro.log.notice("🎤 VoiceConfigurationEditView: Configuration saved for role '\(configuration.role)' and language '\(configuration.language)'")
                    onComplete(true)
                }
            }
        }
        .alert("Configuration Error", isPresented: $showError) {
            Button("OK") { 
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: configuration.language) { oldValue, newValue in
            vxAtelierPro.log.debug("🎤 VoiceConfigurationEditView: Language changed from '\(oldValue)' to '\(newValue)', resetting voice selection")
            configuration.voiceIdentifier = ""
        }
        .onAppear {
            vxAtelierPro.log.debug("🎤 VoiceConfigurationEditView: Loading available voices")
            loadAvailableVoices()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Returns the currently selected voice for preview and display.
    /// Falls back to system default if no specific voice is selected.
    private var selectedVoice: AVSpeechSynthesisVoice? {
        if configuration.voiceIdentifier.isEmpty {
            return AVSpeechSynthesisVoice(language: configuration.language)
        } else {
            return AVSpeechSynthesisVoice(identifier: configuration.voiceIdentifier)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Returns the appropriate SF Symbol name for a given role.
    /// - Parameter role: The role to get an icon for
    /// - Returns: SF Symbol name representing the role
    private func roleIcon(for role: String) -> String {
        switch role {
        case "user":
            return "person.fill"
        case "assistant":
            return "person.2.fill"
        case "system":
            return "gear"
        default:
            return "questionmark.circle"
        }
    }
    
    /// Formats a pitch value for display with "x" suffix
    /// - Parameter pitch: The pitch value to format
    /// - Returns: A formatted string like "1.0x"
    private func formatPitch(_ pitch: Double) -> String {
        // Format the pitch value with proper precision
        let formattedValue: String
        if pitch == 1.0 {
            formattedValue = "1x" // Special case for normal pitch
        } else if pitch == Double(Int(pitch)) {
            formattedValue = "\(Int(pitch))x" // No decimal for whole numbers
        } else if pitch < 1.0 {
            formattedValue = String(format: "%.2gx", pitch) // More precise for lower pitches
        } else {
            formattedValue = String(format: "%.1fx", pitch) // One decimal for higher pitches
        }
        return formattedValue
    }
    
    /// Loads and organizes available system voices.
    /// Groups voices by language and sorts languages by localized name.
    private func loadAvailableVoices() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Group voices by language
        var voiceGroups: [String: [AVSpeechSynthesisVoice]] = [:]
        var languages = Set<String>()
        
        for voice in availableVoices {
            languages.insert(voice.language)
            voiceGroups[voice.language, default: []].append(voice)
        }
        
        // Sort languages by localized name
        availableLanguages = Array(languages).sorted { lang1, lang2 in
            let name1 = Locale.current.localizedString(forIdentifier: lang1) ?? lang1
            let name2 = Locale.current.localizedString(forIdentifier: lang2) ?? lang2
            return name1 < name2
        }
        
        voicesByLanguage = voiceGroups
        vxAtelierPro.log.debug("🎤 VoiceConfigurationEditView: Loaded \(availableVoices.count) voices for \(languages.count) languages")
    }
    
    /// Handles voice preview functionality.
    /// Toggles between playing and stopping the preview, with automatic state management.
    private func previewVoice() {
        if synthesizer.isSpeaking {
            vxAtelierPro.log.debug("🎤 VoiceConfigurationEditView: Stopping voice preview")
            synthesizer.stopSpeaking(at: .immediate)
            isPreviewPlaying = false
            return
        }
        
        guard let voice = selectedVoice else {
            vxAtelierPro.log.error("🎤 VoiceConfigurationEditView: Failed to get voice for preview")
            return
        }
        
        vxAtelierPro.log.debug("🎤 VoiceConfigurationEditView: Starting preview for voice '\(voice.name)'")
        let utterance = AVSpeechUtterance(string: "Hello! This is a preview of my voice.")
        utterance.voice = voice
        
        // Use the speech rate value directly as it's already in AVSpeechUtterance scale
        utterance.rate = Float(configuration.speechRate)
        utterance.pitchMultiplier = Float(configuration.pitchMultiplier)
        
        isPreviewPlaying = true
        synthesizer.speak(utterance)
        
        Task { @MainActor in
            while synthesizer.isSpeaking {
                try? await Task.sleep(for: .milliseconds(100))
            }
            isPreviewPlaying = false
            vxAtelierPro.log.debug("🎤 VoiceConfigurationEditView: Voice preview completed")
        }
    }
    
    /// Returns a label for the current speech rate
    /// - Parameter rate: The speech rate value
    /// - Returns: A descriptive label for the rate
    private func getSpeechRateLabel(_ rate: Double) -> String {
        // Find the closest matching preset label
        let preset = speechRatePresets
            .min(by: { abs($0.value - rate) < abs($1.value - rate) })
        
        return preset?.label ?? "Custom"
    }
}
