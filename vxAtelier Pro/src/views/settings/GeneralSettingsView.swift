import SwiftUI

/// General application preferences.
struct GeneralSettingsView: View {
    @AppStorage(AppSettings.Keys.appearanceStyle) private var appearanceStyle: AppearanceStyle = .system    
    @AppStorage(AppSettings.Keys.showRowToolButtons) private var showRowToolButtons: Bool = AppDefaults.showRowToolButtons
    @AppStorage(AppSettings.Keys.autoNameConversations) private var autoNameConversations: Bool = AppDefaults.autoNameConversations
    @AppStorage(AppSettings.Keys.statusBarVisible) private var statusBarVisible: Bool = AppDefaults.statusBarVisible
    @AppStorage(AppSettings.Keys.showConversationLastMessageLabel) private var showConversationLastMessageLabel: Bool = AppDefaults.showConversationLastMessageLabel
    @AppStorage(AppSettings.Keys.showConversationCreatedLabel) private var showConversationCreatedLabel: Bool = AppDefaults.showConversationCreatedLabel
    @AppStorage(AppSettings.Keys.shouldTerminateAfterLastWindowClosed) private var shouldTerminateAfterLastWindowClosed: Bool = AppDefaults.shouldTerminateAfterLastWindowClosed
    @AppStorage(AppSettings.Keys.conversationTextEditButtonSize) private var conversationTextEditButtonSize: Double = AppDefaults.conversationTextEditButtonSize
    @AppStorage(AppSettings.Keys.autoSendConversationTemplates) private var autoSendConversationTemplates: Bool = AppDefaults.autoSendConversationTemplates
    @AppStorage(AppSettings.Keys.defaultAvatarData) private var defaultAvatarData: Data?
    @AppStorage(AppSettings.Keys.disableAvatar) private var disableAvatar: Bool = AppDefaults.disableAvatar
    @AppStorage(AppSettings.Keys.defaultAvatarSize) private var defaultAvatarSize: Int = AppDefaults.defaultAvatarSize
    @AppStorage(AppSettings.Keys.bubbleFontSize) private var bubbleFontSize: Double = AppDefaults.fontSizeMedium

    var body: some View {
        SettingsPage(title: "General") {
            SettingsFormSection("General Settings") {
                SettingsPickerRow("Appearance", selection: $appearanceStyle) {
                    ForEach(AppearanceStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                SettingsToggleRow("Show Context Menu Button for Lists", isOn: $showRowToolButtons)
                SettingsToggleRow("Automatically name new conversations", isOn: $autoNameConversations)
                SettingsToggleRow("Show Status Bar", isOn: $statusBarVisible)
                SettingsToggleRow("Last Message Timestamp", isOn: $showConversationLastMessageLabel)
                SettingsToggleRow("Creation Timestamp", isOn: $showConversationCreatedLabel)
#if os(macOS)
                SettingsToggleRow(
                    "Terminate after the last window is closed",
                    isOn: $shouldTerminateAfterLastWindowClosed
                )
                SettingsSliderRow(
                    title: "Button size",
                    bounds: 12...48,
                    step: 1,
                    value: $conversationTextEditButtonSize
                )
#endif
                SettingsToggleRow("Auto-send Conversation Templates", isOn: $autoSendConversationTemplates)
            }

            SettingsFormSection("Avatar Settings") {
                AvatarPickerView(title: "Default Avatar", imageData: $defaultAvatarData, size: 48, strokeWidth: 2)
                SettingsToggleRow("Disable Avatar", isOn: $disableAvatar)
                SettingsStepperRow(
                    title: "Avatar Size",
                    bounds: 16...128,
                    step: 2,
                    value: $defaultAvatarSize
                )
                SettingsStepperRow(
                    title: "Bubble Font Size",
                    bounds: 8...28,
                    step: 1,
                    value: Binding(
                        get: { Int(bubbleFontSize) },
                        set: { bubbleFontSize = Double($0) }
                    )
                )
            }
        }
    }
} 
