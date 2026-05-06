import Foundation

/// Tool for listing specific UserDefaults settings managed by AppStorage.
public struct ListSettingsTool: ExecutableLLMTool {
    public let name = "list_settings"
    public let description = "Lists available application settings managed via UserDefaults/AppStorage, showing their keys (for use with read/write tools), data types, current values, writability status, and allowed values for enumerated types."

    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(properties: [:])
    }

    public init() {}

    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        var listDescription = "Available UserDefaults Settings (including current values):\n"
        let userDefaults = UserDefaults.standard

        for (key, info) in LLMToolSettingsRegistry.knownSettings.sorted(by: { $0.key < $1.key }) {
            let typeString = String(describing: info.type)
            let currentValue = userDefaults.object(forKey: key)
            let valueString: String
            if let currentValue = currentValue {
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
            listDescription += ", Current Value: \(valueString)"
            listDescription += "\n"
        }
        listDescription += "\nNote: Some numeric settings have specific ranges (e.g., 'ConversationTextEdit.buttonSize': 12-48)."
        return listDescription
    }
}
