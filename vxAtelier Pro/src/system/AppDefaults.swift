import SwiftUI

struct AppDefaults {
    static let fontSizeSmall = 10.0
    static let fontSizeMedium = 12.0
    static let fontSizeLarge = 14.0
    
    static let paddingSmall = 4.0
    static let paddingMedium = 8.0
    static let paddingLarge = 12.0
    
    static let shadowRadiusSmall = 4.0
    
    static let cornerRadiusSmall = 4.0
    static let cornerRadiusMedium = 8.0
    static let cornerRadiusLarge = 12.0
    
    // UI Colors and Styling
    static let sectionBackgroundOpacity = 0.1
    static let sectionHeaderColor = Color.secondary
    
    static let appearanceStyle = "System"
    
    static let newProjectName = "Unnamed Project"
    static let projectImageSystemName: String = "folder"
    
    static let newDialogName = "Unnamed Dialog"
    static let dialogImageSystemName: String = "document"
    
    static let newApiConfigurationName = "New Configuration"
    
    // Add new defaults for application settings
    static let shouldTerminateAfterLastWindowClosed = true    
    static let dialogTextEditButtonSize = 24.0
    static let disableAvatar = false
    static let defaultAvatarSize = 40
    static let avatarImageSize = 80.0
    static let avatarStrokeWidth = 2.0
    static let autoNameDialogs = true
    static let isMarkdownEnabled = true
    static let isMarkdownTextSelectable = false
    static let statusBarVisible = true
    static let showSystemDialogs = false
    static let autoSendDialogTemplates = true
    static let showRowToolButtons = true
    static let showEmptySections = false 
    static let projectDialogsSortDescending = true
    static let projectDialogsSortType = "conversationDate"
    static let sidebarDialogsSortDescending = true
    static let sidebarDialogsSortType = "conversationDate"
    static let sidebarProjectsSortDescending = false
    static let sidebarProjectsSortType = "alphabetically"
    static let contentFilter = ContentFilter.active.rawValue
    // Conversation label toggles
    static let showConversationLastMessageLabel = true
    static let showConversationCreatedLabel = true
    
    // Developer/advanced settings
    static let makeKeyAndOrderFront = false
    static let autoScrollDebugEnabled = false
    static let autoScrollGateEnabled = false
    static let streamingThrottleEnabled = false
    static let streamingThrottleIntervalMs = 50
    static let streamingDebugEnabled = false
    static let markdownStreamFinalizeOnly = false
    static let showToolCallChips = true
    
    // Permissions
    static let allowSelfSignedCertificates = false
    static let selfSignedCertWhitelist = "[]"
        
    // TTS Settings
    static let ttsAutoplay = true
    static let ttsRepeatMode = "none"  // "none", "one", or "all"
    
    // NOTE: Speech rate and pitch settings are now managed through voice configurations.
    // These values are kept for backward compatibility and as defaults when no voice configuration is available.
    static let ttsSpeechRate = 0.5     // Default normal rate in AVSpeechUtterance
    static let ttsPitchMultiplier = 1.0 // Default normal pitch
    
    struct TTSVoices {   
        static let userLanguage = "en-US"
        static let userVoice = ""  // Empty means system default for language
        static let assistantLanguage = "en-US"
        static let assistantVoice = "com.apple.ttsbundle.Karen-compact"
        static let systemLanguage = "en-US"
        static let systemVoice = ""  // Empty means system default for language
    }
    
    struct ModelContextSizes {
        static let defaultSize = 4096
    }
    
    struct OpenAi {
        static let n = 1            
        static let frequency_penalty: Double = 0.0
        static let presence_penalty: Double? = nil
        static let top_p : Double? = nil
        static let temperature: Double = 0.0
        static let max_tokens: Int? = 2048
        static let model: String = "gpt-4.1-nano"
        static let apiKey = "YOUR API KEY"
        static let baseURL = "https://api.openai.com/v1"
        static let chatCompletionsEndpoint = "/chat/completions"
        static let modelsEndpoint = "/models"
        static let stream: Bool = false
    }
    
    struct Anthropic {
        static let temperature: Double = 0.0
        static let top_p: Double? = nil
        static let top_k: Int? = nil
        static let model: String = "claude-3-sonnet-20240229"
        static let apiKey = "YOUR API KEY"
        static let baseURL = "https://api.anthropic.com"
        static let chatCompletionsEndpoint = "/v1/messages"
        static let modelsEndpoint = "/v1/models"
        static let max_tokens: Int = 4096
        static let stream: Bool = false
    }
    
    struct XAI {
        static let n = 1
        static let frequency_penalty: Double = 0.0
        static let presence_penalty: Double? = nil
        static let top_p : Double? = nil
        static let temperature: Double = 0.0
        static let max_tokens: Int? = 4096
        static let model: String = "grok-2-1212"
        static let apiKey = "YOUR API KEY"
        static let baseURL = "https://api.x.ai/v1"
        static let chatCompletionsEndpoint = "/chat/completions"
        static let modelsEndpoint = "/models"
        static let stream: Bool = false
    }

    struct DeepSeek {
        static let n = 1
        static let frequency_penalty: Double = 0.0
        static let presence_penalty: Double = 0.0
        static let top_p: Double = 0.7
        static let temperature: Double = 0.7
        static let max_tokens: Int = 2048
        static let model: String = "deepseek-chat"
        static let apiKey = "YOUR API KEY"
        static let baseURL = "https://api.deepseek.com/v1"
        static let chatCompletionsEndpoint = "/chat/completions"
        static let modelsEndpoint = "/models"
        static let stream: Bool = false
    }
}

extension AppDefaults {
    /// Resets all user-modifiable settings in UserDefaults to their default values.
    static func resetUserDefaults() {
        let defaults = UserDefaults.standard
        // General settings
        defaults.set(AppDefaults.appearanceStyle, forKey: AppSettings.Keys.appearanceStyle)
        defaults.set(AppDefaults.showRowToolButtons, forKey: AppSettings.Keys.showRowToolButtons)
        defaults.set(AppDefaults.autoNameDialogs, forKey: AppSettings.Keys.autoNameDialogs)
        defaults.set(AppDefaults.statusBarVisible, forKey: AppSettings.Keys.statusBarVisible)
        defaults.set(
            AppDefaults.showConversationLastMessageLabel,
            forKey: AppSettings.Keys.showConversationLastMessageLabel)
        defaults.set(
            AppDefaults.showConversationCreatedLabel,
            forKey: AppSettings.Keys.showConversationCreatedLabel)
        defaults.set(
            AppDefaults.shouldTerminateAfterLastWindowClosed,
            forKey: AppSettings.Keys.shouldTerminateAfterLastWindowClosed)
        defaults.set(
            AppDefaults.dialogTextEditButtonSize,
            forKey: AppSettings.Keys.dialogTextEditButtonSize)
        defaults.set(AppDefaults.autoSendDialogTemplates, forKey: AppSettings.Keys.autoSendDialogTemplates)
        defaults.set(AppDefaults.disableAvatar, forKey: AppSettings.Keys.disableAvatar)
        defaults.set(AppDefaults.defaultAvatarSize, forKey: AppSettings.Keys.defaultAvatarSize)
        defaults.set(AppDefaults.fontSizeMedium, forKey: AppSettings.Keys.bubbleFontSize)
        defaults.removeObject(forKey: AppSettings.Keys.defaultAvatarData)
        // Developer/advanced settings
        defaults.set(AppDefaults.isMarkdownEnabled, forKey: AppSettings.Keys.isMarkdownEnabled)
        defaults.set(
            AppDefaults.isMarkdownTextSelectable,
            forKey: AppSettings.Keys.isMarkdownTextSelectable)
        defaults.set(AppDefaults.showSystemDialogs, forKey: AppSettings.Keys.showSystemDialogs)
        defaults.set(AppDefaults.makeKeyAndOrderFront, forKey: AppSettings.Keys.makeKeyAndOrderFront)
        defaults.set(AppDefaults.autoScrollDebugEnabled, forKey: AppSettings.Keys.autoScrollDebugEnabled)
        defaults.set(AppDefaults.autoScrollGateEnabled, forKey: AppSettings.Keys.autoScrollGateEnabled)
        defaults.set(
            AppDefaults.streamingThrottleEnabled,
            forKey: AppSettings.Keys.streamingThrottleEnabled)
        defaults.set(
            AppDefaults.streamingThrottleIntervalMs,
            forKey: AppSettings.Keys.streamingThrottleIntervalMs)
        defaults.set(AppDefaults.streamingDebugEnabled, forKey: AppSettings.Keys.streamingDebugEnabled)
        defaults.set(
            AppDefaults.markdownStreamFinalizeOnly,
            forKey: AppSettings.Keys.markdownStreamFinalizeOnly)
        defaults.set(AppDefaults.showToolCallChips, forKey: AppSettings.Keys.showToolCallChips)
        // Permissions
        defaults.set(
            AppDefaults.allowSelfSignedCertificates,
            forKey: AppSettings.Keys.allowSelfSignedCertificates)
        defaults.set(AppDefaults.selfSignedCertWhitelist, forKey: AppSettings.Keys.selfSignedCertWhitelist)
        // TTS
        defaults.set(AppDefaults.ttsAutoplay, forKey: AppSettings.Keys.ttsAutoplay)
        defaults.set(AppDefaults.ttsRepeatMode, forKey: AppSettings.Keys.ttsRepeatMode)
        // Sidebar sort
        defaults.set(
            AppDefaults.sidebarDialogsSortDescending,
            forKey: AppSettings.Keys.sidebarDialogsSortDescending)
        defaults.set(AppDefaults.sidebarDialogsSortType, forKey: AppSettings.Keys.sidebarDialogsSortType)
        defaults.set(
            AppDefaults.sidebarProjectsSortDescending,
            forKey: AppSettings.Keys.sidebarProjectsSortDescending)
        defaults.set(AppDefaults.sidebarProjectsSortType, forKey: AppSettings.Keys.sidebarProjectsSortType)
        // Project view sort
        defaults.set(
            AppDefaults.projectDialogsSortDescending,
            forKey: AppSettings.Keys.projectDialogsSortDescending)
        defaults.set(AppDefaults.projectDialogsSortType, forKey: AppSettings.Keys.projectDialogsSortType)
        // Dialog/project filters
        defaults.set(AppDefaults.showEmptySections, forKey: AppSettings.Keys.showEmptySections)
        defaults.set(AppDefaults.contentFilter, forKey: AppSettings.Keys.contentFilter)
        // Add any additional settings as needed
        defaults.synchronize()
    }
}
