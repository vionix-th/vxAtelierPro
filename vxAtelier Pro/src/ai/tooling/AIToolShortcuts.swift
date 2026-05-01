import Foundation
import SwiftData

/// Tool for listing all available Apple Shortcuts
public struct ListShortcutsTool: ExecutableTool {
    public let name = "list_shortcuts"
    public let description = "Lists all Apple Shortcuts configured in the macOS Shortcuts app, returning their unique identifiers (for use with `run_shortcut`) and human-readable names. Can optionally list only shortcuts pre-approved in settings."
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(properties: [:])
    }
    
    public init() {
    }
    
    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        #if os(macOS)
        // Check if we should use restricted list based on configuration
        if let config = configuration,
           let restricted = config["Restricted"] as? Bool,
           restricted,
           let restrictedList = config["RestrictedList"] as? [String: String] {
            
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
    
    public func getDefaultConfiguration() -> [String: Any]? {
        return [
            "Restricted": false,
            "RestrictedList": [
                "ID0001": "Shortcut Name A",
                "ID0002": "Shortcut Name B",
                "ID0003": "Shortcut Name C",
            ]
        ]
    }
}

/// Tool for running a specific Apple Shortcut
public struct RunShortcutTool: ExecutableTool {
    public let name = "run_shortcut"
    public let description = "Executes a specific Apple Shortcut on macOS using either its unique identifier (obtained from `list_shortcuts`) or its exact name. Can optionally pass a string as input to the shortcut."
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(
            properties: [
                "identifier": GenericToolProperty(
                    type: "string",
                    description: "The identifier or name of the shortcut to run"
                ),
                "input": GenericToolProperty(
                    type: "string",
                    description: "Optional input to pass to the shortcut (if it accepts input)"
                )
            ],
            required: ["identifier"]
        )
    }
    
    public init() {
    }
    
    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
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
    
    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}
