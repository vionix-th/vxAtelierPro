import Foundation

typealias LLMToolSettingInfo = AppSettings.SettingDescriptor

/// Thin LLM-tool facade over the canonical app settings registry.
enum LLMToolSettingsRegistry {
    static var knownSettings: [String: LLMToolSettingInfo] {
        AppSettings.settingDescriptors
    }
}
