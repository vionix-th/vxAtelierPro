import SwiftUI

struct DeveloperSettingsView: View {
    @AppStorage("IsMarkdownEnabled") private var isMarkdownEnabled: Bool = AppDefaults.isMarkdownEnabled
    @AppStorage("IsMarkdownTextSelectable") private var isMarkdownTextSelectable: Bool = AppDefaults.isMarkdownTextSelectable
    @AppStorage("ShowUserDialogsOnly") private var showUserDialogsOnly: Bool = AppDefaults.showUserDialogsOnly
    @AppStorage("MakeKeyAndOrderFront") private var makeKeyAndOrderFront: Bool = false
    // New debug/streaming/scrolling flags
    @AppStorage("AutoScrollDebugEnabled") private var autoScrollDebugEnabled: Bool = false
    @AppStorage("AutoScrollGateEnabled") private var autoScrollGateEnabled: Bool = false
    @AppStorage("StreamingThrottleEnabled") private var streamingThrottleEnabled: Bool = false
    @AppStorage("StreamingThrottleIntervalMs") private var streamingThrottleIntervalMs: Int = 50
    @AppStorage("StreamingDebugEnabled") private var streamingDebugEnabled: Bool = false
    @AppStorage("MarkdownStreamFinalizeOnly") private var markdownStreamFinalizeOnly: Bool = false
    @AppStorage("ShowToolCallChips") private var showToolCallChips: Bool = true
    @AppStorage("selfSignedCertWhitelist") private var selfSignedCertWhitelistJSON: String = "[]"
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
                        ToggleRow(title: "Default Markdown Support (for new dialogs)", isOn: $isMarkdownEnabled, titleWidth: 300)
                        ToggleRow(title: "Markdown Selectable", isOn: $isMarkdownTextSelectable, titleWidth: 250)
                        ToggleRow(title: "Show User Dialogs Only", isOn: $showUserDialogsOnly, titleWidth: 250)
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