import Foundation
import SwiftData

/// Tool for renaming a DialogItem
public struct RenameDialogTool: ExecutableTool {
    public let name = "rename_dialog"
    public let description = "Renames a specific chat dialog. Requires the dialog's unique hashed ID (obtainable from 'list_dialogs' or 'get_current_dialog') and the desired new title."
    private let modelContext: ModelContext
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(
            properties: [
                "dialog_id": GenericToolProperty(
                    type: "string",
                    description: "The hashed identifier of the dialog to rename"
                ),
                "new_title": GenericToolProperty(
                    type: "string",
                    description: "The new title for the dialog"
                )
            ],
            required: ["dialog_id", "new_title"]
        )
    }
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        guard let jsonData = arguments.data(using: .utf8) else {
            throw AppError.invalidArguments("Failed to encode arguments as UTF-8 data")
        }
        
        do {
            let args = try JSONDecoder().decode([String: String].self, from: jsonData)
            guard let dialogId = args["dialog_id"],
                  let newTitle = args["new_title"] else {
                throw AppError.invalidArguments("Missing required arguments: dialog_id or new_title")
            }
            
            // Fetch the dialog using the stably hashed ID string
            let descriptor = FetchDescriptor<ConversationItem>()
            let dialogs: [ConversationItem]
            do {
                dialogs = try modelContext.fetch(descriptor)
            } catch {
                await vxAtelierPro.log.error("Failed to fetch \(ConversationItem.self): \(error.localizedDescription)")
                throw AppError.dataFetchFailed(error.localizedDescription)
            }

            guard let dialog = dialogs.first(where: { String(describing: $0.id).stableHash() == dialogId }) else {
                return "Dialog not found"
            }
            
            // Store the dialog ID instead of capturing the dialog instance
            let targetDialogId = dialog.id
            
            // Update the dialog title on the main thread since it's a UI operation
            await MainActor.run {
                // Fetch the dialog again on the main actor
                let descriptor = FetchDescriptor<ConversationItem>()
                if let dialog = try? modelContext.fetch(descriptor).first(where: { $0.id == targetDialogId }) {
                    dialog.title = newTitle
                }
            }
            
            return "Dialog renamed to: \(newTitle)"
        } catch let decodingError as DecodingError {
            await vxAtelierPro.log.error("Failed to decode rename dialog arguments: \(decodingError.localizedDescription)")
            throw AppError.invalidArguments("Invalid argument format: \(decodingError.localizedDescription)")
        } catch {
            await vxAtelierPro.log.error("Failed to rename dialog: \(error.localizedDescription)")
            throw error
        }
    }
    
    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}

/// Tool for listing all dialogs with their IDs and titles
public struct ListDialogsTool: ExecutableTool {
    public let name = "list_dialogs"
    public let description = "Returns a JSON list of all existing chat dialogs, including their unique hashed ID (for use with other dialog tools), title, and purpose."
    private let modelContext: ModelContext
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(properties: [:])
    }
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        // Fetch all dialogs
        let descriptor = FetchDescriptor<ConversationItem>()
        do {
            let dialogs = try modelContext.fetch(descriptor)
            
            if dialogs.isEmpty {
                return "No dialogs found"
            }
            
            // Create a JSON array of dialog objects with stably hashed id and title
            let dialogList = dialogs.map { dialog -> [String: String] in
                return [
                    "id": String(describing: dialog.id).stableHash(),
                    "title": dialog.title,
                    "purpose": String(describing: dialog.purpose)
                ]
            }
            
            // Convert to JSON string
            let jsonData = try JSONEncoder().encode(dialogList)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw AppError.encodingFailed("Failed to encode dialog list as UTF-8 string")
            }
            return jsonString
        } catch let error as AppError {
            await vxAtelierPro.log.error("Failed to process dialogs: \(error.localizedDescription)")
            throw error
        } catch {
            await vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
    
    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}

/// Tool for finding a dialog by its title
public struct FindDialogTool: ExecutableTool {
    public let name = "find_dialog"
    public let description = "Finds the first chat dialog whose title contains the provided search string. Returns a JSON object with the dialog's hashed ID and full title if found, otherwise a 'not found' message."
    private let modelContext: ModelContext
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(
            properties: [
                "title": GenericToolProperty(
                    type: "string",
                    description: "The title to search for"
                )
            ],
            required: ["title"]
        )
    }
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        guard let jsonData = arguments.data(using: .utf8) else {
            throw AppError.invalidArguments("Failed to encode arguments as UTF-8 data")
        }
        
        do {
            let args = try JSONDecoder().decode([String: String].self, from: jsonData)
            guard let title = args["title"] else {
                throw AppError.invalidArguments("Missing required argument: title")
            }
            
            // Fetch all dialogs
            let descriptor = FetchDescriptor<ConversationItem>()
            let dialogs = try modelContext.fetch(descriptor)
            
            // Find the first dialog with matching title
            if let dialog = dialogs.first(where: { $0.title.contains(title) }) {
                let dialogInfo: [String: String] = [
                    "id": String(describing: dialog.id).stableHash(),
                    "title": dialog.title
                ]
                
                // Convert to JSON string
                let jsonData = try JSONEncoder().encode(dialogInfo)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    throw AppError.encodingFailed("Failed to encode dialog information as UTF-8 string")
                }
                return jsonString
            } else {
                return "No dialog found with title containing: \(title)"
            }
        } catch let error as DecodingError {
            await vxAtelierPro.log.error("Failed to decode find dialog arguments: \(error.localizedDescription)")
            throw AppError.invalidArguments("Invalid argument format: \(error.localizedDescription)")
        } catch let error as AppError {
            await vxAtelierPro.log.error("Failed to process dialog: \(error.localizedDescription)")
            throw error
        } catch {
            await vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
    
    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}

/// Tool for getting the current dialog's ID
public struct CurrentDialogTool: ExecutableTool {
    public let name = "get_current_dialog"
    public let description = "Returns a JSON object containing the unique hashed ID, title, and purpose of the chat dialog currently active in the application context."
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(properties: [:])
    }
    
    public init() {
    }
    
    public func execute(arguments: String, configuration: [String: Any]? = nil, context: Any? = nil) async throws -> String {
        // Get the current dialog ID from configuration
        guard let dialogItem = context as? ConversationItem else {
            return "No current dialog information available in context"
        }
        
        // Create a response object with dialog info
        let response: [String: String] = [
            "id": String(describing: dialogItem.id).stableHash(),
            "title": dialogItem.title,
            "purpose": String(describing: dialogItem.purpose)
        ]
        
        // Convert to JSON string
        do {
            let jsonData = try JSONEncoder().encode(response)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw AppError.encodingFailed("Failed to encode dialog information as UTF-8 string")
            }
            return jsonString
        } catch let error as EncodingError {
            await vxAtelierPro.log.error("Failed to encode current dialog information: \(error.localizedDescription)")
            throw AppError.encodingFailed(error.localizedDescription)
        } catch {
            await vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
    
    public func getDefaultConfiguration() -> [String: Any]? {
        return nil
    }
}
