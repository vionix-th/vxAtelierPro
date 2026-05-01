import SwiftUI

struct DeveloperSettingsView: View {
    @AppStorage(AppSettings.Keys.isMarkdownEnabled) private var isMarkdownEnabled: Bool = AppDefaults.isMarkdownEnabled
    @AppStorage(AppSettings.Keys.isMarkdownTextSelectable) private var isMarkdownTextSelectable: Bool = AppDefaults.isMarkdownTextSelectable
    @AppStorage(AppSettings.Keys.showSystemConversations) private var showSystemConversations: Bool = AppDefaults.showSystemConversations
    @AppStorage(AppSettings.Keys.makeKeyAndOrderFront) private var makeKeyAndOrderFront: Bool = false
    // New debug/streaming/scrolling flags
    @AppStorage(AppSettings.Keys.autoScrollDebugEnabled) private var autoScrollDebugEnabled: Bool = false
    @AppStorage(AppSettings.Keys.autoScrollGateEnabled) private var autoScrollGateEnabled: Bool = false
    @AppStorage(AppSettings.Keys.streamingThrottleEnabled) private var streamingThrottleEnabled: Bool = false
    @AppStorage(AppSettings.Keys.streamingThrottleIntervalMs) private var streamingThrottleIntervalMs: Int = 50
    @AppStorage(AppSettings.Keys.streamingDebugEnabled) private var streamingDebugEnabled: Bool = false
    @AppStorage(AppSettings.Keys.markdownStreamFinalizeOnly) private var markdownStreamFinalizeOnly: Bool = false
    @AppStorage(AppSettings.Keys.showToolCallChips) private var showToolCallChips: Bool = true
    @AppStorage(AppSettings.Keys.selfSignedCertWhitelist) private var selfSignedCertWhitelistJSON: String = "[]"
    @State private var selfSignedCertWhitelist: [String] = []

    private func decodeWhitelist(from json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    private func encodeWhitelist(_ whitelist: [String]) -> String {
        if let data = try? JSONEncoder().encode(whitelist), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppDefaults.paddingLarge) {
                SettingsSectionView(title: "Developer Settings") {
                    VStack(spacing: AppDefaults.paddingMedium) {
                        ToggleRow(title: "Default Markdown Support (for new conversations)", isOn: $isMarkdownEnabled, titleWidth: 300)
                        ToggleRow(title: "Markdown Selectable", isOn: $isMarkdownTextSelectable, titleWidth: 250)
                        ToggleRow(title: "Show System Conversations (Debug)", isOn: $showSystemConversations, titleWidth: 250)
                        ToggleRow(title: "Show Tool Call Chips", isOn: $showToolCallChips, titleWidth: 250)
                        ToggleRow(title: "Make Key and Order Front", isOn: $makeKeyAndOrderFront, titleWidth: 250)
                    }
                }

                SettingsSectionView(title: "Conversation & Streaming Debug") {
                    VStack(spacing: AppDefaults.paddingMedium) {
                        ToggleRow(title: "Auto-Scroll Debug Logs", isOn: $autoScrollDebugEnabled, titleWidth: 250)
                        ToggleRow(title: "Auto-Scroll Gate (Bottom Stickiness)", isOn: $autoScrollGateEnabled, titleWidth: 250)
                        Divider()
                        ToggleRow(title: "Streaming Throttle Enabled", isOn: $streamingThrottleEnabled, titleWidth: 250)
                        StepperRow(title: "Streaming Throttle Interval (ms)", bounds: 10...500, step: 10, value: $streamingThrottleIntervalMs, titleWidth: 250)
                        ToggleRow(title: "Streaming Debug Logs", isOn: $streamingDebugEnabled, titleWidth: 250)
                        Divider()
                        ToggleRow(title: "Markdown: Finalize Only on Stream", isOn: $markdownStreamFinalizeOnly, titleWidth: 250)
                    }
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge)
        }
        .navigationTitle("Developer")
        .onAppear {
            selfSignedCertWhitelist = decodeWhitelist(from: selfSignedCertWhitelistJSON)
        }
        .onChange(of: selfSignedCertWhitelist) {
            selfSignedCertWhitelistJSON = encodeWhitelist(selfSignedCertWhitelist)
        }
    }
} 
