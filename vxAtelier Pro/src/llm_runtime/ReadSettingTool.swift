import Foundation

/// Tool for reading a specific UserDefaults setting managed by AppStorage.
public struct ReadSettingTool: ExecutableLLMTool {
    public let name = "read_setting"
    public let description = "Reads the current value of a specific application setting stored in UserDefaults, identified by its key (obtained from 'list_settings')."

    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(
            properties: [
                "setting_key": GenericLLMToolProperty(
                    type: "string",
                    description: "The key of the setting to read (must be a known key from 'list_settings')"
                )
            ],
            required: ["setting_key"]
        )
    }

    public init() {}

    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        else {
            return "Error: Invalid argument format. Expected a JSON object with 'setting_key'."
        }

        guard let settingKey = args["setting_key"] as? String else {
            return "Error: Missing required argument: setting_key"
        }

        guard let settingInfo = LLMToolSettingsRegistry.knownSettings[settingKey] else {
            return "Error: Setting key '\(settingKey)' is not recognized or supported. Use 'list_settings' to see available keys."
        }

        let userDefaults = UserDefaults.standard

        if settingKey == "defaultAvatar" {
            let dataExists = userDefaults.data(forKey: settingKey) != nil
            return "Setting '\(settingKey)' (Data): \(dataExists ? "Exists" : "Does not exist")"
        }

        if let value = userDefaults.object(forKey: settingKey) {
            let expectedType = settingInfo.type
            if type(of: value) == expectedType || expectedType == Double.self && value is NSNumber {
                return "Setting '\(settingKey)': \(value)"
            } else if expectedType == Int.self && value is NSNumber {
                return "Setting '\(settingKey)': \((value as! NSNumber).intValue)"
            } else {
                await vxAtelierPro.log.warning("Type mismatch for key '\(settingKey)'. Expected \(expectedType), got \(type(of: value))")
                return "Setting '\(settingKey)': (Value exists, but type mismatch detected: \(type(of: value)))"
            }
        } else {
            return "Setting '\(settingKey)' not found or has no value."
        }
    }
}
