import AVFoundation
import SwiftUI

struct VoiceConfigurationDraft {
    let language: String
    let voiceIdentifier: String
    let role: String
    let speechRate: Double
    let pitchMultiplier: Double
}

struct VoiceConfigurationEditView: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: VoiceConfigurationItem
    let isNewConfig: Bool
    let configurations: [VoiceConfigurationItem]
    var onCancel: () -> Void
    var onSave: (VoiceConfigurationDraft) -> String?

    @State private var language: String
    @State private var voiceIdentifier: String
    @State private var role: String
    @State private var speechRate: Double
    @State private var pitchMultiplier: Double
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var voicesByLanguage: [String: [AVSpeechSynthesisVoice]] = [:]
    @State private var availableLanguages: [String] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isPreviewPlaying = false

    private let synthesizer = AVSpeechSynthesizer()
    private let roles = ["user", "assistant", "system"]
    private let speechRatePresets: [(label: String, value: Double)] = [
        ("Very Slow", 0.05),
        ("Slower", 0.3),
        ("Normal", 0.5),
        ("Faster", 0.6),
        ("Very Fast", 0.7)
    ]

    init(
        configuration: VoiceConfigurationItem,
        isNewConfig: Bool,
        configurations: [VoiceConfigurationItem],
        onCancel: @escaping () -> Void,
        onSave: @escaping (VoiceConfigurationDraft) -> String?
    ) {
        self.configuration = configuration
        self.isNewConfig = isNewConfig
        self.configurations = configurations
        self.onCancel = onCancel
        self.onSave = onSave
        _language = State(initialValue: configuration.language)
        _voiceIdentifier = State(initialValue: configuration.voiceIdentifier)
        _role = State(initialValue: configuration.role)
        _speechRate = State(initialValue: configuration.speechRate)
        _pitchMultiplier = State(initialValue: configuration.pitchMultiplier)
    }

    var body: some View {
        SettingsPage(title: isNewConfig ? "New Voice Configuration" : "Edit Voice Configuration") {
            SettingsFormSection("Basic Settings") {
                SettingsPickerRow("Role", selection: $role) {
                    ForEach(roles, id: \.self) { role in
                        Label(role.capitalized, systemImage: roleIcon(for: role))
                            .tag(role)
                    }
                }

                SettingsPickerRow("Language", selection: $language) {
                    ForEach(availableLanguages, id: \.self) { language in
                        Text(Locale.current.localizedString(forIdentifier: language) ?? language)
                            .tag(language)
                    }
                }
            }

            SettingsFormSection("Voice Selection") {
                SettingsPickerRow("Voice", selection: $voiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(voicesByLanguage[language] ?? [], id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }

                SettingsPickerRow("Speech Rate", selection: $speechRate) {
                    ForEach(speechRatePresets, id: \.value) { preset in
                        Text(preset.label).tag(preset.value)
                    }
                }

                SettingsSliderRow(
                    title: "Pitch",
                    bounds: 0.5...2.0,
                    step: 0.05,
                    value: $pitchMultiplier
                )

                if let voice = selectedVoice {
                    LabeledContent("Current Voice") {
                        HStack {
                            Text("\(voice.name), \(speechRateLabel) speed")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                previewVoice()
                            } label: {
                                Label(
                                    isPreviewPlaying ? "Stop" : "Preview",
                                    systemImage: isPreviewPlaying ? "stop.circle.fill" : "play.circle.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .settingsCancel) {
                Button("Cancel") {
                    synthesizer.stopSpeaking(at: .immediate)
                    onCancel()
                }
            }
            ToolbarItem(placement: .settingsConfirm) {
                Button("Done") {
                    save()
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
        .onChange(of: language) {
            voiceIdentifier = ""
        }
        .onAppear(perform: loadAvailableVoices)
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        if voiceIdentifier.isEmpty {
            AVSpeechSynthesisVoice(language: language)
        } else {
            AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        }
    }

    private var speechRateLabel: String {
        speechRatePresets
            .min(by: { abs($0.value - speechRate) < abs($1.value - speechRate) })?
            .label ?? "Custom"
    }

    private func save() {
        let existingConfig = configurations.first { item in
            item.language == language &&
            item.role == role &&
            item.persistentModelID != configuration.persistentModelID
        }

        if existingConfig != nil {
            errorMessage = "A voice configuration for '\(role)' with language '\(language)' already exists."
            showError = true
            return
        }

        let draft = VoiceConfigurationDraft(
            language: language,
            voiceIdentifier: voiceIdentifier,
            role: role,
            speechRate: speechRate,
            pitchMultiplier: pitchMultiplier
        )
        if let saveError = onSave(draft) {
            errorMessage = saveError
            showError = true
        } else {
            onCancel()
        }
    }

    private func loadAvailableVoices() {
        availableVoices = AVSpeechSynthesisVoice.speechVoices()
        var voiceGroups: [String: [AVSpeechSynthesisVoice]] = [:]
        var languages = Set<String>()

        for voice in availableVoices {
            languages.insert(voice.language)
            voiceGroups[voice.language, default: []].append(voice)
        }

        availableLanguages = Array(languages).sorted { lhs, rhs in
            let lhsName = Locale.current.localizedString(forIdentifier: lhs) ?? lhs
            let rhsName = Locale.current.localizedString(forIdentifier: rhs) ?? rhs
            return lhsName < rhsName
        }
        if !availableLanguages.contains(language) {
            availableLanguages.insert(language, at: 0)
        }
        voicesByLanguage = voiceGroups
    }

    private func previewVoice() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isPreviewPlaying = false
            return
        }

        guard let voice = selectedVoice else {
            errorMessage = "Failed to get voice for preview."
            showError = true
            return
        }

        let utterance = AVSpeechUtterance(string: "Hello. This is a preview of my voice.")
        utterance.voice = voice
        utterance.rate = Float(speechRate)
        utterance.pitchMultiplier = Float(pitchMultiplier)

        isPreviewPlaying = true
        synthesizer.speak(utterance)

        Task { @MainActor in
            while synthesizer.isSpeaking {
                try? await Task.sleep(for: .milliseconds(100))
            }
            isPreviewPlaying = false
        }
    }

    private func roleIcon(for role: String) -> String {
        switch role {
        case "user": "person.fill"
        case "assistant": "person.2.fill"
        case "system": "gear"
        default: "questionmark.circle"
        }
    }
}
