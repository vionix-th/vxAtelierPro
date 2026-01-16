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
    
    static let appearanceStyle = "Auto"
    
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
    // Conversation label toggles
    static let showConversationLastMessageLabel = true
    static let showConversationCreatedLabel = true
        
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
        defaults.set(AppDefaults.appearanceStyle, forKey: "appearanceStyle")
        defaults.set(AppDefaults.showRowToolButtons, forKey: "showRowToolButtons")
        defaults.set(AppDefaults.autoNameDialogs, forKey: "autoNameDialogs")
        defaults.set(AppDefaults.statusBarVisible, forKey: "statusBarVisible")
        defaults.set(AppDefaults.showConversationLastMessageLabel, forKey: "showConversationLastMessageLabel")
        defaults.set(AppDefaults.showConversationCreatedLabel, forKey: "showConversationCreatedLabel")
        defaults.set(AppDefaults.shouldTerminateAfterLastWindowClosed, forKey: "shouldTerminateAfterLastWindowClosed")
        defaults.set(AppDefaults.dialogTextEditButtonSize, forKey: "DialogTextEdit.buttonSize")
        defaults.set(AppDefaults.autoSendDialogTemplates, forKey: "autoSendDialogTemplates")
        defaults.set(AppDefaults.disableAvatar, forKey: "DisableAvatar")
        defaults.set(AppDefaults.defaultAvatarSize, forKey: "DefaultAvatarSize")
        defaults.set(AppDefaults.fontSizeMedium, forKey: "BubbleFontSize")
        // Developer/advanced settings
        defaults.set(AppDefaults.isMarkdownEnabled, forKey: "IsMarkdownEnabled")
        defaults.set(AppDefaults.isMarkdownTextSelectable, forKey: "IsMarkdownTextSelectable")
        defaults.set(AppDefaults.showSystemDialogs, forKey: "ShowSystemDialogs")
        // Permissions
        defaults.set(false, forKey: "allowSelfSignedCertificates")
        defaults.set("[]", forKey: "selfSignedCertWhitelist")
        // TTS
        defaults.set(AppDefaults.ttsAutoplay, forKey: "TTSAutoplay")
        defaults.set(AppDefaults.ttsRepeatMode, forKey: "TTSRepeatMode")
        // Sidebar sort
        defaults.set(true, forKey: "SidebarDialogsSortOrderDescending")
        defaults.set("conversationDate", forKey: "SidebarDialogsSortType")
        defaults.set(false, forKey: "SidebarProjectsSortOrderDescending")
        defaults.set("alphabetically", forKey: "SidebarProjectsSortType")
        // Project view sort
        defaults.set(AppDefaults.projectDialogsSortDescending, forKey: "ProjectDialogsSortOrderDescending")
        defaults.set(AppDefaults.projectDialogsSortType, forKey: "ProjectDialogsSortType")
        // Dialog/project filters
        defaults.set(false, forKey: "ShowEmptySections")
        defaults.set(NavigationMode.chats.rawValue, forKey: "NavigationMode")
        // Add any additional settings as needed
        defaults.synchronize()
    }
}
