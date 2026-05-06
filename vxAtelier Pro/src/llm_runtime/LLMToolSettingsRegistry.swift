import Foundation

struct LLMToolSettingInfo {
    let type: Any.Type
    let allowedValues: [String]?
    let isWritable: Bool

    init(type: Any.Type, allowedValues: [String]? = nil, isWritable: Bool = true) {
        self.type = type
        self.allowedValues = allowedValues
        self.isWritable = isWritable
    }
}

enum LLMToolSettingsRegistry {
    static let knownSettings: [String: LLMToolSettingInfo] = [
        "defaultModel": .init(type: String.self),
        "shouldTerminateAfterLastWindowClosed": .init(type: Bool.self),
        "appearanceStyle": .init(type: String.self, allowedValues: ["System", "Light", "Dark"]),
        "showRowToolButtons": .init(type: Bool.self),
        "ConversationTextEdit.buttonSize": .init(type: Double.self),
        "DisableAvatar": .init(type: Bool.self),
        "DefaultAvatarSize": .init(type: Int.self),
        "BubbleFontSize": .init(type: Double.self),
        "autoNameConversations": .init(type: Bool.self),
        "statusBarVisible": .init(type: Bool.self),
        "showConversationLastMessageLabel": .init(type: Bool.self),
        "showConversationCreatedLabel": .init(type: Bool.self),
        "defaultAvatar": .init(type: Data.self, isWritable: false),
        "IsMarkdownEnabled": .init(type: Bool.self),
        "IsMarkdownTextSelectable": .init(type: Bool.self),
        "ShowSystemConversations": .init(type: Bool.self),
        "ProjectConversationsSortOrderDescending": .init(type: Bool.self),
        "ProjectConversationsSortType": .init(type: String.self, allowedValues: ["conversationDate", "lastMessageDate", "alphabetically"]),
        "autoSendConversationTemplates": .init(type: Bool.self),
        "TTSAutoplay": .init(type: Bool.self),
        "TTSRepeatMode": .init(type: String.self, allowedValues: ["none", "one", "all"]),
        "allowSelfSignedCertificates": .init(type: Bool.self),
        "selfSignedCertWhitelist": .init(type: String.self)
    ]
}
