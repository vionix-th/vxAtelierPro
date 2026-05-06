import Foundation
import SwiftData

/// Tool for listing all available Apple Shortcuts
public struct ListShortcutsTool: ExecutableLLMTool, ConfigurableLLMTool {
    public let name = "list_shortcuts"
    public let description = "Lists all Apple Shortcuts configured in the macOS Shortcuts app, returning their unique identifiers (for use with `run_shortcut`) and human-readable names. Can optionally list only shortcuts pre-approved in settings."
    
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(properties: [:])
    }

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
    
    public init() {
    }
    
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let configuration = call.configuration
        #if os(macOS)
        // Check if we should use restricted list based on configuration
        if configuration["Restricted"]?.boolValue == true,
           let restrictedListObject = configuration["RestrictedList"]?.objectValue {
            let restrictedList = restrictedListObject.compactMapValues(\.stringValue)
            
            // Return only the restricted list of shortcuts
            let shortcutsList = restrictedList.map { shortcutId, shortcutName -> [String: String] in
                return [
                    "id": shortcutId,
                    "name": shortcutName
                ]
            }
            
            // Convert to JSON string
            if let jsonData = try? JSONEncoder().encode(shortcutsList),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            } else {
                return "Failed to encode restricted shortcuts list"
            }
        }
        
        // If not restricted, get all shortcuts from Shortcuts.app
        let shortcuts = await ShortcutsManager.shared.getAllShortcuts()
        
        if shortcuts.isEmpty {
            return "No shortcuts found. Use the 'Add Shortcut' button in settings to add shortcuts."
        }
        
        // Create a JSON array with shortcut info
        let shortcutsList = shortcuts.map { shortcut -> [String: String] in
            return [
                "id": shortcut.id,
                "name": shortcut.name
            ]
        }
        
        // Convert to JSON string
        if let jsonData = try? JSONEncoder().encode(shortcutsList),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        } else {
            return "Failed to encode shortcuts list"
        }
        #else
        return "This feature is only available on macOS"
        #endif
    }
    
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

/// Tool for running a specific Apple Shortcut
public struct RunShortcutTool: ExecutableLLMTool {
    public let name = "run_shortcut"
    public let description = "Executes a specific Apple Shortcut on macOS using either its unique identifier (obtained from `list_shortcuts`) or its exact name. Can optionally pass a string as input to the shortcut."
    
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
    
    public init() {
    }
    
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        #if os(macOS)
        guard let jsonData = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode([String: String].self, from: jsonData),
              let identifier = args["identifier"]
        else {
            throw LLMProviderError.invalidConfiguration("Shortcut tool arguments must include identifier.")
        }
        
        // Extract the optional input parameter
        let input = args["input"]
        
        // Pass both identifier and input to the ShortcutsManager
        return await ShortcutsManager.shared.runShortcut(name: identifier, input: input)
        #else
        return "This feature is only available on macOS"
        #endif
    }
}
