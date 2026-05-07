import Foundation
import SwiftData

/// Executable tool that lists available Apple Shortcuts, optionally restricted by configuration.
public struct ListShortcutsTool: ExecutableLLMTool, ConfigurableLLMTool {
    public let name = "list_shortcuts"
    public let description = "Lists all Apple Shortcuts configured in the macOS Shortcuts app, returning their unique identifiers (for use with `run_shortcut`) and human-readable names. Can optionally list only shortcuts pre-approved in settings."
    
    /// Accepts no call-time arguments.
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(properties: [:])
    }

    /// Allows settings to restrict the visible shortcut list.
    var configurationSchema: any LLMToolParameters {
        GenericLLMToolParameters(
            properties: [
                "Restricted": GenericLLMToolProperty(
                    type: "boolean",
                    description: "When true, only shortcuts listed in RestrictedList are returned."
                ),
                "RestrictedList": GenericLLMToolProperty(
                    type: "object",
                    description: "Dictionary of allowed shortcut identifiers to display names."
                )
            ]
        )
    }
    
    /// Creates a shortcut-listing tool.
    public init() {
    }
    
    /// Returns configured or discovered shortcuts as JSON.
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let configuration = call.configuration
        #if os(macOS)
        if configuration["Restricted"]?.boolValue == true,
           let restrictedListObject = configuration["RestrictedList"]?.objectValue {
            let restrictedList = restrictedListObject.compactMapValues(\.stringValue)
            
            let shortcutsList = restrictedList.map { shortcutId, shortcutName -> [String: String] in
                return [
                    "id": shortcutId,
                    "name": shortcutName
                ]
            }
            
            if let jsonData = try? JSONEncoder().encode(shortcutsList),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            } else {
                throw LLMToolExecutionError.executionFailed("Failed to encode restricted shortcuts list.")
            }
        }
        
        let shortcuts = await ShortcutsManager.shared.getAllShortcuts()
        
        if shortcuts.isEmpty {
            return "No shortcuts found. Use the 'Add Shortcut' button in settings to add shortcuts."
        }
        
        let shortcutsList = shortcuts.map { shortcut -> [String: String] in
            return [
                "id": shortcut.id,
                "name": shortcut.name
            ]
        }
        
        if let jsonData = try? JSONEncoder().encode(shortcutsList),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        } else {
            throw LLMToolExecutionError.executionFailed("Failed to encode shortcuts list.")
        }
        #else
        throw LLMToolExecutionError.unavailable("This feature is only available on macOS.")
        #endif
    }
    
    /// Provides a disabled restriction baseline with example values for settings UI materialization.
    func defaultConfiguration() -> [String: JSONValue] {
        [
            "Restricted": .boolean(false),
            "RestrictedList": .object([
                "ID0001": .string("Shortcut Name A"),
                "ID0002": .string("Shortcut Name B"),
                "ID0003": .string("Shortcut Name C")
            ])
        ]
    }
}

/// Executable tool that runs an Apple Shortcut by identifier or exact name.
public struct RunShortcutTool: ExecutableLLMTool {
    public let name = "run_shortcut"
    public let description = "Executes a specific Apple Shortcut on macOS using either its unique identifier (obtained from `list_shortcuts`) or its exact name. Can optionally pass a string as input to the shortcut."
    
    /// Requires a shortcut identifier and accepts optional string input.
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(
            properties: [
                "identifier": GenericLLMToolProperty(
                    type: "string",
                    description: "The identifier or name of the shortcut to run"
                ),
                "input": GenericLLMToolProperty(
                    type: "string",
                    description: "Optional input to pass to the shortcut (if it accepts input)"
                )
            ],
            required: ["identifier"]
        )
    }
    
    /// Creates a shortcut execution tool.
    public init() {
    }
    
    /// Runs the selected shortcut and returns the Shortcuts manager output.
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        #if os(macOS)
        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode([String: String].self, from: jsonData),
              let identifier = args["identifier"]
        else {
            throw LLMProviderError.invalidConfiguration("Shortcut tool arguments must include identifier.")
        }
        
        let input = args["input"]
        
        return await ShortcutsManager.shared.runShortcut(name: identifier, input: input)
        #else
        throw LLMToolExecutionError.unavailable("This feature is only available on macOS.")
        #endif
    }
}
