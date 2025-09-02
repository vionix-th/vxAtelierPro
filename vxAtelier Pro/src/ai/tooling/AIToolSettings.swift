import Foundation

// MARK: - Shared Setting Definitions

private struct SettingInfo {
    let type: Any.Type
    let allowedValues: [String]?
    let isWritable: Bool

    // Explicit initializer to handle defaults
    init(type: Any.Type, allowedValues: [String]? = nil, isWritable: Bool = true) {
        self.type = type
        self.allowedValues = allowedValues
        self.isWritable = isWritable
    }
}

private let knownSettings: [String: SettingInfo] = [
    "defaultModel": .init(type: String.self),
    "shouldTerminateAfterLastWindowClosed": .init(type: Bool.self),
    "appearanceStyle": .init(type: String.self, allowedValues: ["System", "Light", "Dark"]),
    "showRowToolButtons": .init(type: Bool.self),
    "DialogTextEdit.buttonSize": .init(type: Double.self), // Range: 12...48
    "DisableAvatar": .init(type: Bool.self),
    "DefaultAvatarSize": .init(type: Int.self), // Range: 16...128, Step: 2
    "BubbleFontSize": .init(type: Double.self), // Range: 8...28
    "AutoNameDialogs": .init(type: Bool.self), // Legacy, keep for compatibility
    "autoNameDialogs": .init(type: Bool.self), // Used in GeneralSettingsView
    "statusBarVisible": .init(type: Bool.self),
    "showConversationLastMessageLabel": .init(type: Bool.self), // Used in GeneralSettingsView
    "showConversationCreatedLabel": .init(type: Bool.self), // Used in GeneralSettingsView
    "defaultAvatar": .init(type: Data.self, isWritable: false), // Special case: Read-only for existence check
    "IsMarkdownEnabled": .init(type: Bool.self),
    "IsMarkdownTextSelectable": .init(type: Bool.self),
    "ShowUserDialogsOnly": .init(type: Bool.self),
    "AutoSendDialogTemplates": .init(type: Bool.self),
    "autoSendDialogTemplates": .init(type: Bool.self), // Used in GeneralSettingsView
    "TTSAutoplay": .init(type: Bool.self),
    "TTSRepeatMode": .init(type: String.self, allowedValues: ["none", "one", "all"]),
    "allowSelfSignedCertificates": .init(type: Bool.self), // Used in PermissionsSettingsView
    "selfSignedCertWhitelist": .init(type: String.self), // JSON-encoded array, used in DeveloperSettingsView
    "selfSignedCertWhitelistJSON": .init(type: String.self) // JSON-encoded array, used in PermissionsSettingsView
]

// MARK: - List Settings Tool

/// Tool for listing specific UserDefaults settings managed by AppStorage.
public struct ListSettingsTool: ExecutableTool {
    public let name = "list_settings"
    public let description = "Lists available application settings managed via UserDefaults/AppStorage, showing their keys (for use with read/write tools), data types, current values, writability status, and allowed values for enumerated types."

    public var parameters: any AIToolParameters {
        GenericToolParameters(properties: [:]) // No parameters needed for list
    }

    public init() {}

    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        var listDescription = "Available UserDefaults Settings (including current values):\n"
        let userDefaults = UserDefaults.standard // Get UserDefaults instance

        for (key, info) in knownSettings.sorted(by: { $0.key < $1.key }) {
            let typeString = String(describing: info.type)
            let currentValue = userDefaults.object(forKey: key) // Fetch current value
            let valueString: String
            if let currentValue = currentValue {
                // Handle potential NSNumber storage for Int/Double
                if info.type == Int.self, let num = currentValue as? NSNumber {
                    valueString = String(num.intValue)
                } else if info.type == Double.self, let num = currentValue as? NSNumber {
                    valueString = String(num.doubleValue)
                } else {
                    valueString = String(describing: currentValue)
                }
            } else {
                valueString = "(Not Set)"
            }

            listDescription += "- Key: '\(key)', Type: \(typeString)"
            if let allowed = info.allowedValues, !allowed.isEmpty {
                listDescription += ", Allowed Values: [\(allowed.joined(separator: ", "))]"
            }
            if !info.isWritable {
                 listDescription += " (Read-only via tool)"
            }
            listDescription += ", Current Value: \(valueString)" // Add current value
            listDescription += "\n"
        }
        // Add notes about ranges if needed, e.g.:
        listDescription += "\nNote: Some numeric settings have specific ranges (e.g., 'DialogTextEdit.buttonSize': 12-48)."
        return listDescription
    }

    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}

// MARK: - Read Setting Tool

/// Tool for reading a specific UserDefaults setting managed by AppStorage.
public struct ReadSettingTool: ExecutableTool {
    public let name = "read_setting"
    public let description = "Reads the current value of a specific application setting stored in UserDefaults, identified by its key (obtained from 'list_settings')."

    public var parameters: any AIToolParameters {
        GenericToolParameters(
            properties: [
                "setting_key": GenericToolProperty(
                    type: "string",
                    description: "The key of the setting to read (must be a known key from 'list_settings')"
                )
            ],
            required: ["setting_key"]
        )
    }

    public init() {}

    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        else {
             // Don't throw, return error string
             return "Error: Invalid argument format. Expected a JSON object with 'setting_key'."
        }

        guard let settingKey = args["setting_key"] as? String else {
            return "Error: Missing required argument: setting_key"
        }

        guard let settingInfo = knownSettings[settingKey] else {
            return "Error: Setting key '\(settingKey)' is not recognized or supported. Use 'list_settings' to see available keys."
        }

        let userDefaults = UserDefaults.standard

        // Special handling for read-only Data check
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

    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}

// MARK: - Write Setting Tool

/// Tool for writing a specific UserDefaults setting managed by AppStorage.
public struct WriteSettingTool: ExecutableTool {
    public let name = "write_setting"
    public let description = "Writes a new value to a specific, writable application setting in UserDefaults. Requires the setting key (from 'list_settings') and the new value matching the setting's type (e.g., 'new_string_value' for String). Use 'list_settings' first to check key, type, and writability."

    public var parameters: any AIToolParameters {
        GenericToolParameters(
            properties: [
                "setting_key": GenericToolProperty(
                    type: "string",
                    description: "The key of the setting to write (must be a known, writable key)"
                ),
                "new_string_value": GenericToolProperty(
                    type: "string",
                    description: "The new value if the setting is a String."
                ),
                "new_bool_value": GenericToolProperty(
                    type: "boolean",
                    description: "The new value if the setting is a Boolean."
                ),
                "new_int_value": GenericToolProperty(
                    type: "integer",
                    description: "The new value if the setting is an Integer."
                ),
                "new_double_value": GenericToolProperty(
                    type: "number",
                    description: "The new value if the setting is a Double/Number."
                )
            ],
            required: ["setting_key"] // One of the new_*_value arguments is also required, based on type
        )
    }

    public init() {}

    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        else {
             // Don't throw, return error string
             return "Error: Invalid argument format. Expected a JSON object with 'setting_key' and one 'new_*_value'."
        }

        guard let settingKey = args["setting_key"] as? String else {
            return "Error: Missing required argument: setting_key"
        }

        guard let settingInfo = knownSettings[settingKey] else {
            return "Error: Setting key '\(settingKey)' is not recognized or supported. Use 'list_settings' to see available keys."
        }

        // Check writability first
        guard settingInfo.isWritable else {
            return "Error: Setting key '\(settingKey)' is read-only and cannot be modified by this tool."
        }

        let userDefaults = UserDefaults.standard
        let expectedType = settingInfo.type
        var valueToWrite: Any?

        // Determine which value parameter was provided and try to cast/validate
        if expectedType == String.self {
            guard let val = args["new_string_value"] as? String else {
                 return "Error: Missing or incorrect type for 'new_string_value' argument for setting '\(settingKey)'."
             }
             // Validate against allowed values if applicable
             if let allowed = settingInfo.allowedValues, !allowed.contains(val) {
                 return "Error: Invalid value '\(val)' for setting '\(settingKey)'. Allowed values: [\(allowed.joined(separator: ", "))]"
             }
             valueToWrite = val
        } else if expectedType == Bool.self {
            guard let val = args["new_bool_value"] as? Bool else {
                 return "Error: Missing or incorrect type for 'new_bool_value' argument for setting '\(settingKey)'."
             }
            valueToWrite = val
        } else if expectedType == Int.self {
             guard let val = args["new_int_value"] as? Int else {
                 return "Error: Missing or incorrect type for 'new_int_value' argument for setting '\(settingKey)'."
             }
            // Add range validation if known (example for DefaultAvatarSize)
            if settingKey == "DefaultAvatarSize" && !(16...128).contains(val) {
                 return "Error: Value \(val) for '\(settingKey)' is outside the allowed range (16-128)."
             }
            valueToWrite = val
        } else if expectedType == Double.self {
             // Accept Double or Int for Double settings
             var doubleVal: Double?
             if let val = args["new_double_value"] as? Double {
                 doubleVal = val
             } else if let val = args["new_double_value"] as? Int {
                 doubleVal = Double(val)
             }
             guard let finalDoubleVal = doubleVal else {
                  return "Error: Missing or incorrect type for 'new_double_value' argument for setting '\(settingKey)'. Expected number."
              }

            // Add range validation if known (example for DialogTextEdit.buttonSize)
             if settingKey == "DialogTextEdit.buttonSize" && !(12...48).contains(finalDoubleVal) {
                 return "Error: Value \(finalDoubleVal) for '\(settingKey)' is outside the allowed range (12-48)."
             }
             if settingKey == "BubbleFontSize" && !(8...28).contains(finalDoubleVal) {
                  return "Error: Value \(finalDoubleVal) for '\(settingKey)' is outside the allowed range (8-28)."
              }
            valueToWrite = finalDoubleVal
        }

        guard let finalValue = valueToWrite else {
            // This should theoretically not be reached if type checks above are exhaustive
            return "Error: Could not determine value to write for setting '\(settingKey)'. Type mismatch or missing value argument."
        }

        // Write the value
        userDefaults.set(finalValue, forKey: settingKey)
        await vxAtelierPro.log.info("Setting '\(settingKey)' updated via AI tool to '\(String(describing: finalValue))'.")
        return "Successfully updated setting '\(settingKey)' to '\(finalValue)' (Type: \(expectedType))."
    }

    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}