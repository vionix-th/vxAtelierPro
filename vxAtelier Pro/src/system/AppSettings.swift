import Foundation

/// Single source of truth for all UserDefaults keys used by the app.
/// Keep keys here; use them with @AppStorage or direct UserDefaults access.
enum AppSettings {
    struct SettingDescriptor {
        let key: String
        let type: Any.Type
        let allowedValues: [String]?
        let isWritable: Bool
        let intRange: ClosedRange<Int>?
        let doubleRange: ClosedRange<Double>?

        init(
            key: String,
            type: Any.Type,
            allowedValues: [String]? = nil,
            isWritable: Bool = true,
            intRange: ClosedRange<Int>? = nil,
            doubleRange: ClosedRange<Double>? = nil
        ) {
            self.key = key
            self.type = type
            self.allowedValues = allowedValues
            self.isWritable = isWritable
            self.intRange = intRange
            self.doubleRange = doubleRange
        }
    }

    enum Keys {
        // Navigation & layout
        static let showEmptySections = "ShowEmptySections"
        static let contentFilter = "ContentFilter"
        static let statusBarVisible = "statusBarVisible"
        static let statusBarLayoutStyle = "statusBarLayoutStyle"
        static let appearanceStyle = "appearanceStyle"
        static let showRowToolButtons = "showRowToolButtons"
        static let showSystemConversations = "ShowSystemConversations"
        static let selectedSettingsDestination = "SelectedSettingsDestination"
        static let selectedMacSettingsSection = "SelectedMacSettingsSection"

        // Sidebar sorting
        static let sidebarConversationsSortDescending = "SidebarConversationsSortOrderDescending"
        static let sidebarConversationsSortType = "SidebarConversationsSortType"
        static let sidebarProjectsSortDescending = "SidebarProjectsSortOrderDescending"
        static let sidebarProjectsSortType = "SidebarProjectsSortType"

        // Project view sorting
        static let projectConversationsSortDescending = "ProjectConversationsSortOrderDescending"
        static let projectConversationsSortType = "ProjectConversationsSortType"

        // Conversation labels
        static let showConversationLastMessageLabel = "showConversationLastMessageLabel"
        static let showConversationCreatedLabel = "showConversationCreatedLabel"

        // Conversation creation
        static let autoNameConversations = "autoNameConversations"
        static let autoSendConversationTemplates = "autoSendConversationTemplates"

        // Message input
        static let conversationTextEditButtonSize = "ConversationTextEdit.buttonSize"

        // Avatar & bubble presentation
        static let disableAvatar = "DisableAvatar"
        static let defaultAvatarSize = "DefaultAvatarSize"
        static let defaultAvatarData = "defaultAvatar"
        static let bubbleFontSize = "BubbleFontSize"

        // Markdown & toolchips
        static let isMarkdownEnabled = "IsMarkdownEnabled"
        static let isMarkdownTextSelectable = "IsMarkdownTextSelectable"
        static let markdownStreamFinalizeOnly = "MarkdownStreamFinalizeOnly"
        static let showToolCallChips = "ShowToolCallChips"

        // Developer options
        static let makeKeyAndOrderFront = "MakeKeyAndOrderFront"
        static let autoScrollDebugEnabled = "AutoScrollDebugEnabled"
        static let autoScrollGateEnabled = "AutoScrollGateEnabled"
        static let streamingThrottleEnabled = "StreamingThrottleEnabled"
        static let streamingThrottleIntervalMs = "StreamingThrottleIntervalMs"
        static let streamingDebugEnabled = "StreamingDebugEnabled"

        // Permissions
        static let allowSelfSignedCertificates = "allowSelfSignedCertificates"
        static let selfSignedCertWhitelist = "selfSignedCertWhitelist"

        // TTS
        static let ttsEntryPauseMs = "TTSEntryPauseMs"
        static let ttsRepeatMode = "TTSRepeatMode"
        static let ttsActivePlaylistID = "TTSActivePlaylistID"

        // Lifecycle
        static let shouldTerminateAfterLastWindowClosed = "shouldTerminateAfterLastWindowClosed"
        static let launchInRecoveryMode = "LaunchInRecoveryMode"

        // Logging filters
        static let popupLogTypeFilters = "popupLogTypeFilters"
        static let statusBarLogTypeFilters = "statusBarLogTypeFilters"
    }

    static let settingDescriptors: [String: SettingDescriptor] = [
        Keys.shouldTerminateAfterLastWindowClosed: .init(key: Keys.shouldTerminateAfterLastWindowClosed, type: Bool.self),
        Keys.appearanceStyle: .init(key: Keys.appearanceStyle, type: String.self, allowedValues: ["System", "Light", "Dark"]),
        Keys.showRowToolButtons: .init(key: Keys.showRowToolButtons, type: Bool.self),
        Keys.conversationTextEditButtonSize: .init(key: Keys.conversationTextEditButtonSize, type: Double.self, doubleRange: 12...48),
        Keys.disableAvatar: .init(key: Keys.disableAvatar, type: Bool.self),
        Keys.defaultAvatarSize: .init(key: Keys.defaultAvatarSize, type: Int.self, intRange: 16...128),
        Keys.bubbleFontSize: .init(key: Keys.bubbleFontSize, type: Double.self, doubleRange: 8...28),
        Keys.autoNameConversations: .init(key: Keys.autoNameConversations, type: Bool.self),
        Keys.statusBarVisible: .init(key: Keys.statusBarVisible, type: Bool.self),
        Keys.statusBarLayoutStyle: .init(
            key: Keys.statusBarLayoutStyle,
            type: String.self,
            allowedValues: StatusBarLayoutStyle.allCases.map(\.rawValue)
        ),
        Keys.showConversationLastMessageLabel: .init(key: Keys.showConversationLastMessageLabel, type: Bool.self),
        Keys.showConversationCreatedLabel: .init(key: Keys.showConversationCreatedLabel, type: Bool.self),
        Keys.defaultAvatarData: .init(key: Keys.defaultAvatarData, type: Data.self, isWritable: false),
        Keys.isMarkdownEnabled: .init(key: Keys.isMarkdownEnabled, type: Bool.self),
        Keys.isMarkdownTextSelectable: .init(key: Keys.isMarkdownTextSelectable, type: Bool.self),
        Keys.showSystemConversations: .init(key: Keys.showSystemConversations, type: Bool.self),
        Keys.selectedSettingsDestination: .init(
            key: Keys.selectedSettingsDestination,
            type: String.self,
            allowedValues: SettingsDestination.allCases.map(\.rawValue)
        ),
        Keys.selectedMacSettingsSection: .init(
            key: Keys.selectedMacSettingsSection,
            type: String.self,
            allowedValues: MacOSSettingsSection.allCases.map(\.rawValue)
        ),
        Keys.projectConversationsSortDescending: .init(key: Keys.projectConversationsSortDescending, type: Bool.self),
        Keys.projectConversationsSortType: .init(
            key: Keys.projectConversationsSortType,
            type: String.self,
            allowedValues: ["conversationDate", "lastMessageDate", "alphabetically"]
        ),
        Keys.autoSendConversationTemplates: .init(key: Keys.autoSendConversationTemplates, type: Bool.self),
        Keys.ttsEntryPauseMs: .init(key: Keys.ttsEntryPauseMs, type: Int.self, intRange: 0...5000),
        Keys.ttsRepeatMode: .init(key: Keys.ttsRepeatMode, type: String.self, allowedValues: ["none", "one", "all"]),
        Keys.allowSelfSignedCertificates: .init(key: Keys.allowSelfSignedCertificates, type: Bool.self),
        Keys.selfSignedCertWhitelist: .init(key: Keys.selfSignedCertWhitelist, type: String.self)
    ]
}
