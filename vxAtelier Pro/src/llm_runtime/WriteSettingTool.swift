import Foundation

/// Tool for writing a specific UserDefaults setting managed by AppStorage.
public struct WriteSettingTool: ExecutableLLMTool {
    public let name = "write_setting"
    public let description = "Writes a new value to a specific, writable application setting in UserDefaults. Requires the setting key (from 'list_settings') and the new value matching the setting's type (e.g., 'new_string_value' for String). Use 'list_settings' first to check key, type, and writability."

    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(
            properties: [
                "setting_key": GenericLLMToolProperty(
                    type: "string",
                    description: "The key of the setting to write (must be a known, writable key)"
                ),
                "new_string_value": GenericLLMToolProperty(
                    type: "string",
                    description: "The new value if the setting is a String."
                ),
                "new_bool_value": GenericLLMToolProperty(
                    type: "boolean",
                    description: "The new value if the setting is a Boolean."
                ),
                "new_int_value": GenericLLMToolProperty(
                    type: "integer",
                    description: "The new value if the setting is an Integer."
                ),
                "new_double_value": GenericLLMToolProperty(
                    type: "number",
                    description: "The new value if the setting is a Double/Number."
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
            throw LLMToolExecutionError.invalidArguments("Invalid argument format. Expected a JSON object with 'setting_key' and one 'new_*_value'.")
        }

        guard let settingKey = args["setting_key"] as? String else {
            throw LLMToolExecutionError.invalidArguments("Missing required argument: setting_key")
        }

        guard let settingInfo = LLMToolSettingsRegistry.knownSettings[settingKey] else {
            throw LLMToolExecutionError.invalidArguments("Setting key '\(settingKey)' is not recognized or supported. Use 'list_settings' to see available keys.")
        }

        guard settingInfo.isWritable else {
            throw LLMToolExecutionError.unavailable("Setting key '\(settingKey)' is read-only and cannot be modified by this tool.")
        }

        let userDefaults = UserDefaults.standard
        let expectedType = settingInfo.type
        var valueToWrite: Any?

        if expectedType == String.self {
            guard let val = args["new_string_value"] as? String else {
                throw LLMToolExecutionError.invalidArguments("Missing or incorrect type for 'new_string_value' argument for setting '\(settingKey)'.")
            }
            if let allowed = settingInfo.allowedValues, !allowed.contains(val) {
                throw LLMToolExecutionError.invalidArguments("Invalid value '\(val)' for setting '\(settingKey)'. Allowed values: [\(allowed.joined(separator: ", "))]")
            }
            valueToWrite = val
        } else if expectedType == Bool.self {
            guard let val = args["new_bool_value"] as? Bool else {
                throw LLMToolExecutionError.invalidArguments("Missing or incorrect type for 'new_bool_value' argument for setting '\(settingKey)'.")
            }
            valueToWrite = val
        } else if expectedType == Int.self {
            guard let val = args["new_int_value"] as? Int else {
                throw LLMToolExecutionError.invalidArguments("Missing or incorrect type for 'new_int_value' argument for setting '\(settingKey)'.")
            }
            if settingKey == "DefaultAvatarSize" && !(16...128).contains(val) {
                throw LLMToolExecutionError.invalidArguments("Value \(val) for '\(settingKey)' is outside the allowed range (16-128).")
            }
            valueToWrite = val
        } else if expectedType == Double.self {
            var doubleVal: Double?
            if let val = args["new_double_value"] as? Double {
                doubleVal = val
            } else if let val = args["new_double_value"] as? Int {
                doubleVal = Double(val)
            }
            guard let finalDoubleVal = doubleVal else {
                throw LLMToolExecutionError.invalidArguments("Missing or incorrect type for 'new_double_value' argument for setting '\(settingKey)'. Expected number.")
            }

            if settingKey == "ConversationTextEdit.buttonSize" && !(12...48).contains(finalDoubleVal) {
                throw LLMToolExecutionError.invalidArguments("Value \(finalDoubleVal) for '\(settingKey)' is outside the allowed range (12-48).")
            }
            if settingKey == "BubbleFontSize" && !(8...28).contains(finalDoubleVal) {
                throw LLMToolExecutionError.invalidArguments("Value \(finalDoubleVal) for '\(settingKey)' is outside the allowed range (8-28).")
            }
            valueToWrite = finalDoubleVal
        }

        guard let finalValue = valueToWrite else {
            throw LLMToolExecutionError.invalidArguments("Could not determine value to write for setting '\(settingKey)'. Type mismatch or missing value argument.")
        }

        userDefaults.set(finalValue, forKey: settingKey)
        await vxAtelierPro.log.info("Setting '\(settingKey)' updated via LLM tool to '\(String(describing: finalValue))'.")
        return "Successfully updated setting '\(settingKey)' to '\(finalValue)' (Type: \(expectedType))."
    }
}
