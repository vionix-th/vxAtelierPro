import AVFoundation
import SwiftData
import SwiftUI

struct TTSSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\VoiceConfigurationItem.language)]) private var voiceConfigurations: [VoiceConfigurationItem]
    @AppStorage(AppSettings.Keys.ttsAutoplay) private var ttsAutoplay: Bool = AppDefaults.ttsAutoplay
    @AppStorage(AppSettings.Keys.ttsRepeatMode) private var ttsRepeatMode: String = AppDefaults.ttsRepeatMode
    @State private var editingConfig: EditingConfig?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var confirmation: SettingsConfirmation?

    private struct EditingConfig: Identifiable {
        let id = UUID()
        var config: VoiceConfigurationItem
        var isNew: Bool
    }

    var body: some View {
        SettingsInsetGroupedListPage(title: "Speech") {
            List {
                Section {
                    SettingsToggleRow("Autoplay Next", isOn: $ttsAutoplay)
                    SettingsPickerRow("Repeat Mode", selection: $ttsRepeatMode) {
                        Text("None").tag("none")
                        Text("One").tag("one")
                        Text("All").tag("all")
                    }
                } header: {
                    Text("Text to Speech Settings")
                }

                Section {
                    if voiceConfigurations.isEmpty {
                        LabeledContent {
                            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                                Label("No Voice Configurations", systemImage: "waveform")
                                Text("Add a voice configuration to customize speech for different roles.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            EmptyView()
                        }
                    } else {
                        ForEach(voiceConfigurations) { config in
                            SettingsEntityRow(
                                title: config.role.capitalized,
                                subtitle: Locale.current.localizedString(forIdentifier: config.language) ?? config.language,
                                metadata: voiceName(for: config),
                                systemImages: config.voiceIdentifier.isEmpty ? [] : ["waveform"]
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editConfiguration(config)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    editConfiguration(config)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    confirmDelete(config)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    editConfiguration(config)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    confirmDelete(config)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        editingConfig = EditingConfig(
                            config: VoiceConfigurationItem(language: "en-US", voiceIdentifier: "", role: "user"),
                            isNew: true
                        )
                    } label: {
                        Label("Add Configuration", systemImage: "plus")
                    }
                } header: {
                    Text("Voice Configurations")
                }
            }
        }
        .sheet(item: $editingConfig) { editing in
            NavigationStack {
                VoiceConfigurationEditView(
                    configuration: editing.config,
                    isNewConfig: editing.isNew,
                    configurations: voiceConfigurations,
                    onCancel: {
                        editingConfig = nil
                    },
                    onSave: { draft in
                        saveConfiguration(editing, draft: draft)
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
        .settingsConfirmationDialog($confirmation)
    }

    private func voiceName(for config: VoiceConfigurationItem) -> String? {
        guard !config.voiceIdentifier.isEmpty,
              let voice = AVSpeechSynthesisVoice(identifier: config.voiceIdentifier) else {
            return nil
        }
        return voice.name
    }

    private func editConfiguration(_ config: VoiceConfigurationItem) {
        editingConfig = EditingConfig(config: config, isNew: false)
    }

    private func confirmDelete(_ config: VoiceConfigurationItem) {
        confirmation = SettingsConfirmation(
            title: "Delete Voice Configuration",
            message: "Delete the \(config.role) voice for \(Locale.current.localizedString(forIdentifier: config.language) ?? config.language)?",
            confirmTitle: "Delete",
            action: { deleteConfiguration(config) }
        )
    }

    private func saveConfiguration(_ editing: EditingConfig, draft: VoiceConfigurationDraft) -> String? {
        let oldLanguage = editing.config.language
        let oldVoiceIdentifier = editing.config.voiceIdentifier
        let oldRole = editing.config.role
        let oldSpeechRate = editing.config.speechRate
        let oldPitchMultiplier = editing.config.pitchMultiplier

        editing.config.language = draft.language
        editing.config.voiceIdentifier = draft.voiceIdentifier
        editing.config.role = draft.role
        editing.config.speechRate = draft.speechRate
        editing.config.pitchMultiplier = draft.pitchMultiplier

        do {
            if editing.isNew {
                try queryManager.insert(editing.config)
            } else {
                try queryManager.saveContext()
            }
            return nil
        } catch {
            editing.config.language = oldLanguage
            editing.config.voiceIdentifier = oldVoiceIdentifier
            editing.config.role = oldRole
            editing.config.speechRate = oldSpeechRate
            editing.config.pitchMultiplier = oldPitchMultiplier
            return "Failed to save configuration: \(error.localizedDescription)"
        }
    }

    private func deleteConfiguration(_ config: VoiceConfigurationItem) {
        do {
            try queryManager.delete(config)
        } catch {
            errorMessage = "Failed to delete configuration: \(error.localizedDescription)"
            showError = true
        }
    }
}
