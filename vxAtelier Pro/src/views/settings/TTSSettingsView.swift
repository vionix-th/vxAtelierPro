import SwiftUI

struct TTSSettingsView: View {
    @AppStorage("TTSAutoplay") private var ttsAutoplay: Bool = AppDefaults.ttsAutoplay
    @AppStorage("TTSRepeatMode") private var ttsRepeatMode: String = AppDefaults.ttsRepeatMode
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppDefaults.paddingLarge) {
                // TTS Settings Section
                SettingsSectionView(title: "Text to Speech Settings") {
                    VStack(spacing: AppDefaults.paddingMedium) {
                        ToggleRow(title: "Autoplay Next", isOn: $ttsAutoplay)
                        Picker("Repeat Mode", selection: $ttsRepeatMode) {
                            Text("None").tag("none")
                            Text("One").tag("one")
                            Text("All").tag("all")
                        }
                        Text("Note: Speech rate and pitch settings have been moved to individual voice configurations.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
                // Voice Configurations Section
                SettingsSectionView(title: "Voice Configurations") {
                    VStack {
                        VoiceConfigurationListView()
                    }
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge)
        }
        .navigationTitle("Speech")
    }
} 