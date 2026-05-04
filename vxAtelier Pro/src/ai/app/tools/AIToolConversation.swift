import Foundation
import SwiftData

/// Tool for renaming a ConversationItem
public struct RenameConversationTool: ExecutableTool {
    public let name = "rename_conversation"
    public let description = "Renames a specific chat conversation. Requires the conversation's unique hashed ID (obtainable from 'list_conversations' or 'get_current_conversation') and the desired new title."
    private let modelContext: ModelContext
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(
            properties: [
                "conversation_id": GenericToolProperty(
                    type: "string",
                    description: "The hashed identifier of the conversation to rename"
                ),
                "new_title": GenericToolProperty(
                    type: "string",
                    description: "The new title for the conversation"
                )
            ],
            required: ["conversation_id", "new_title"]
        )
    }
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func execute(_ call: ToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        guard let jsonData = arguments.data(using: .utf8) else {
            throw AppError.invalidArguments("Failed to encode arguments as UTF-8 data")
        }
        
        do {
            let args = try JSONDecoder().decode([String: String].self, from: jsonData)
            guard let conversationId = args["conversation_id"],
                  let newTitle = args["new_title"] else {
                throw AppError.invalidArguments("Missing required arguments: conversation_id or new_title")
            }
            
            // Fetch the conversation using the stably hashed ID string
            let descriptor = FetchDescriptor<ConversationItem>()
            let conversations: [ConversationItem]
            do {
                conversations = try modelContext.fetch(descriptor)
            } catch {
                await vxAtelierPro.log.error("Failed to fetch \(ConversationItem.self): \(error.localizedDescription)")
                throw AppError.dataFetchFailed(error.localizedDescription)
            }

            guard let conversation = conversations.first(where: { String(describing: $0.id).stableHash() == conversationId }) else {
                return "Conversation not found"
            }
            
            // Store the conversation ID instead of capturing the conversation instance
            let targetConversationId = conversation.id
            
            // Update the conversation title on the main thread since it's a UI operation
            await MainActor.run {
                // Fetch the conversation again on the main actor
                let descriptor = FetchDescriptor<ConversationItem>()
                if let conversation = try? modelContext.fetch(descriptor).first(where: { $0.id == targetConversationId }) {
                    conversation.title = newTitle
                }
            }
            
            return "Conversation renamed to: \(newTitle)"
        } catch let decodingError as DecodingError {
            await vxAtelierPro.log.error("Failed to decode rename conversation arguments: \(decodingError.localizedDescription)")
            throw AppError.invalidArguments("Invalid argument format: \(decodingError.localizedDescription)")
        } catch {
            await vxAtelierPro.log.error("Failed to rename conversation: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Tool for listing all conversations with their IDs and titles
public struct ListConversationsTool: ExecutableTool {
    public let name = "list_conversations"
    public let description = "Returns a JSON list of all existing chat conversations, including their unique hashed ID (for use with other conversation tools), title, and purpose."
    private let modelContext: ModelContext
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(properties: [:])
    }
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func execute(_ call: ToolExecutionCall) async throws -> String {
        // Fetch all conversations
        let descriptor = FetchDescriptor<ConversationItem>()
        do {
            let conversations = try modelContext.fetch(descriptor)
            
            if conversations.isEmpty {
                return "No conversations found"
            }
            
            // Create a JSON array of conversation objects with stably hashed id and title
            let conversationList = conversations.map { conversation -> [String: String] in
                return [
                    "id": String(describing: conversation.id).stableHash(),
                    "title": conversation.title,
                    "purpose": String(describing: conversation.purpose)
                ]
            }
            
            // Convert to JSON string
            let jsonData = try JSONEncoder().encode(conversationList)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw AppError.encodingFailed("Failed to encode conversation list as UTF-8 string")
            }
            return jsonString
        } catch let error as AppError {
            await vxAtelierPro.log.error("Failed to process conversations: \(error.localizedDescription)")
            throw error
        } catch {
            await vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
}

/// Tool for finding a conversation by its title
public struct FindConversationTool: ExecutableTool {
    public let name = "find_conversation"
    public let description = "Finds the first chat conversation whose title contains the provided search string. Returns a JSON object with the conversation's hashed ID and full title if found, otherwise a 'not found' message."
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
    
    func execute(_ call: ToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        guard let jsonData = arguments.data(using: .utf8) else {
            throw AppError.invalidArguments("Failed to encode arguments as UTF-8 data")
        }
        
        do {
            let args = try JSONDecoder().decode([String: String].self, from: jsonData)
            guard let title = args["title"] else {
                throw AppError.invalidArguments("Missing required argument: title")
            }
            
            // Fetch all conversations
            let descriptor = FetchDescriptor<ConversationItem>()
            let conversations = try modelContext.fetch(descriptor)
            
            // Find the first conversation with matching title
            if let conversation = conversations.first(where: { $0.title.contains(title) }) {
                let conversationInfo: [String: String] = [
                    "id": String(describing: conversation.id).stableHash(),
                    "title": conversation.title
                ]
                
                // Convert to JSON string
                let jsonData = try JSONEncoder().encode(conversationInfo)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    throw AppError.encodingFailed("Failed to encode conversation information as UTF-8 string")
                }
                return jsonString
            } else {
                return "No conversation found with title containing: \(title)"
            }
        } catch let error as DecodingError {
            await vxAtelierPro.log.error("Failed to decode find conversation arguments: \(error.localizedDescription)")
            throw AppError.invalidArguments("Invalid argument format: \(error.localizedDescription)")
        } catch let error as AppError {
            await vxAtelierPro.log.error("Failed to process conversation: \(error.localizedDescription)")
            throw error
        } catch {
            await vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
}

/// Tool for getting the current conversation's ID
public struct CurrentConversationTool: ExecutableTool {
    public let name = "get_current_conversation"
    public let description = "Returns a JSON object containing the unique hashed ID, title, and purpose of the chat conversation currently active in the application context."
    
    public var parameters: any AIToolParameters {
        GenericToolParameters(properties: [:])
    }
    
    public init() {
    }
    
    func execute(_ call: ToolExecutionCall) async throws -> String {
        let conversationItem = call.context.conversation
        
        // Create a response object with conversation info
        let response: [String: String] = [
            "id": String(describing: conversationItem.id).stableHash(),
            "title": conversationItem.title,
            "purpose": String(describing: conversationItem.purpose)
        ]
        
        // Convert to JSON string
        do {
            let jsonData = try JSONEncoder().encode(response)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw AppError.encodingFailed("Failed to encode conversation information as UTF-8 string")
            }
            return jsonString
        } catch let error as EncodingError {
            await vxAtelierPro.log.error("Failed to encode current conversation information: \(error.localizedDescription)")
            throw AppError.encodingFailed(error.localizedDescription)
        } catch {
            await vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
}
