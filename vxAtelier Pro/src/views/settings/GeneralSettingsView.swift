import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("appearanceStyle") private var appearanceStyle: AppearanceStyle = .system    
    @AppStorage("showRowToolButtons") private var showRowToolButtons: Bool = AppDefaults.showRowToolButtons
    @AppStorage("autoNameDialogs") private var autoNameDialogs: Bool = AppDefaults.autoNameDialogs
    @AppStorage("statusBarVisible") private var statusBarVisible: Bool = AppDefaults.statusBarVisible
    @AppStorage("showConversationLastMessageLabel") private var showConversationLastMessageLabel: Bool = AppDefaults.showConversationLastMessageLabel
    @AppStorage("showConversationCreatedLabel") private var showConversationCreatedLabel: Bool = AppDefaults.showConversationCreatedLabel
    @AppStorage("shouldTerminateAfterLastWindowClosed") private var shouldTerminateAfterLastWindowClosed: Bool = AppDefaults.shouldTerminateAfterLastWindowClosed
    @AppStorage("DialogTextEdit.buttonSize") private var dialogTextEditButtonSize: Double = AppDefaults.dialogTextEditButtonSize
    @AppStorage("autoSendDialogTemplates") private var autoSendDialogTemplates: Bool = AppDefaults.autoSendDialogTemplates
    @AppStorage("defaultAvatar") private var defaultAvatarData: Data?
    @AppStorage("DisableAvatar") private var disableAvatar: Bool = AppDefaults.disableAvatar
    @AppStorage("DefaultAvatarSize") private var defaultAvatarSize: Int = AppDefaults.defaultAvatarSize
    @AppStorage("BubbleFontSize") private var bubbleFontSize: Double = AppDefaults.fontSizeMedium

    var body: some View {
        ScrollView {
            VStack(spacing: AppDefaults.paddingLarge) {
                SettingsSectionView(title: "General Settings") {
                    VStack(spacing: AppDefaults.paddingMedium) {
                        HStack {
                            Text("Appearance")
                            Spacer()
                            Picker("Appearance", selection: $appearanceStyle) {
                                ForEach(AppearanceStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .labelsHidden()
                            #if os(macOS)
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 250)
                            #endif
                        }
                        ToggleRow(title: "Show Context Menu Button for Lists", isOn: $showRowToolButtons)
                        ToggleRow(title: "Automatically name new dialogs", isOn: $autoNameDialogs)
                        ToggleRow(title: "Show Status Bar", isOn: $statusBarVisible)
                        ToggleRow(title: "Last Message Timestamp", isOn: $showConversationLastMessageLabel)
                        ToggleRow(title: "Creation Timestamp", isOn: $showConversationCreatedLabel)
#if os(macOS)
                        ToggleRow(title: "Terminate after the last window is closed", isOn: $shouldTerminateAfterLastWindowClosed, titleWidth: 250)
                        SliderRow(title: "Button size", bounds: 12...48, step: 1, value: Binding(get: { dialogTextEditButtonSize }, set: { dialogTextEditButtonSize = $0 }))
#endif
                        ToggleRow(title: "Auto-send Dialog Templates", isOn: $autoSendDialogTemplates, titleWidth: 250)
                    }
                }
                SettingsSectionView(title: "Avatar Settings") {
                    VStack(spacing: AppDefaults.paddingMedium) {
                        AvatarPickerView(title: "Default Avatar", imageData: $defaultAvatarData, size: 48, strokeWidth: 2)
                        ToggleRow(title: "Disable Avatar", isOn: $disableAvatar, titleWidth: 250)
                        StepperRow(title: "Avatar Size", bounds: 16...128, step: 2, value: Binding(get: { defaultAvatarSize }, set: { defaultAvatarSize = $0 }))
                        StepperRow(title: "Bubble Font Size", bounds: 8...28, step: 1, value: Binding(get: { Int(bubbleFontSize) }, set: { bubbleFontSize = Double($0) }))
                    }
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge)
        }
        .navigationTitle("General")
    }
} 