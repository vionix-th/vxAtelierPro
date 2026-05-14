import SwiftUI

/// Developer-focused preferences and diagnostics.
struct DeveloperSettingsView: View {
    @AppStorage(AppSettings.Keys.isMarkdownEnabled) private var isMarkdownEnabled: Bool = AppDefaults.isMarkdownEnabled
    @AppStorage(AppSettings.Keys.isMarkdownTextSelectable) private var isMarkdownTextSelectable: Bool = AppDefaults.isMarkdownTextSelectable
    @AppStorage(AppSettings.Keys.showSystemConversations) private var showSystemConversations: Bool = AppDefaults.showSystemConversations
    @AppStorage(AppSettings.Keys.makeKeyAndOrderFront) private var makeKeyAndOrderFront: Bool = false
    @AppStorage(AppSettings.Keys.autoScrollDebugEnabled) private var autoScrollDebugEnabled: Bool = false
    @AppStorage(AppSettings.Keys.autoScrollGateEnabled) private var autoScrollGateEnabled: Bool = false
    @AppStorage(AppSettings.Keys.streamingThrottleEnabled) private var streamingThrottleEnabled: Bool = false
    @AppStorage(AppSettings.Keys.streamingThrottleIntervalMs) private var streamingThrottleIntervalMs: Int = 50
    @AppStorage(AppSettings.Keys.streamingDebugEnabled) private var streamingDebugEnabled: Bool = false
    @AppStorage(AppSettings.Keys.markdownStreamFinalizeOnly) private var markdownStreamFinalizeOnly: Bool = false
    @AppStorage(AppSettings.Keys.showToolCallChips) private var showToolCallChips: Bool = true

    var body: some View {
        SettingsPage(title: "Developer") {
            SettingsFormSection("Developer Settings") {
                SettingsToggleRow("Default Markdown Support (for new conversations)", isOn: $isMarkdownEnabled)
                SettingsToggleRow("Markdown Selectable", isOn: $isMarkdownTextSelectable)
                SettingsToggleRow("Show System Conversations (Debug)", isOn: $showSystemConversations)
                SettingsToggleRow("Show Tool Call Chips", isOn: $showToolCallChips)
                SettingsToggleRow("Make Key and Order Front", isOn: $makeKeyAndOrderFront)
            }

            SettingsFormSection("Conversation & Streaming Debug") {
                SettingsToggleRow("Auto-Scroll Debug Logs", isOn: $autoScrollDebugEnabled)
                SettingsToggleRow("Auto-Scroll Gate (Bottom Stickiness)", isOn: $autoScrollGateEnabled)
                SettingsToggleRow("Streaming Throttle Enabled", isOn: $streamingThrottleEnabled)
                SettingsStepperRow(
                    title: "Streaming Throttle Interval (ms)",
                    bounds: 10...500,
                    step: 10,
                    value: $streamingThrottleIntervalMs
                )
                SettingsToggleRow("Streaming Debug Logs", isOn: $streamingDebugEnabled)
                SettingsToggleRow("Markdown: Finalize Only on Stream", isOn: $markdownStreamFinalizeOnly)
            }
        }
    }
}
