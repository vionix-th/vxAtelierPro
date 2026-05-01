import Foundation

/// Single source of truth for all UserDefaults keys used by the app.
/// Keep keys here; use them with @AppStorage or direct UserDefaults access.
enum AppSettings {
    enum Keys {
        // Navigation & layout
        static let showEmptySections = "ShowEmptySections"
        static let contentFilter = "ContentFilter"
        static let statusBarVisible = "statusBarVisible"
        static let appearanceStyle = "appearanceStyle"
        static let showRowToolButtons = "showRowToolButtons"
        static let showSystemConversations = "ShowSystemConversations"

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
        static let ttsAutoplay = "TTSAutoplay"
        static let ttsRepeatMode = "TTSRepeatMode"

        // Lifecycle
        static let shouldTerminateAfterLastWindowClosed = "shouldTerminateAfterLastWindowClosed"

        // Logging filters
        static let popupLogTypeFilters = "popupLogTypeFilters"
        static let statusBarLogTypeFilters = "statusBarLogTypeFilters"
    }
}
