import Foundation
import SwiftData

/// Executable tool that renames a conversation selected by stable hashed ID.
public struct RenameConversationTool: ExecutableLLMTool {
    public let name = "rename_conversation"
    public let description = "Renames a specific chat conversation. Requires the conversation's unique hashed ID (obtainable from 'list_conversations' or 'get_current_conversation') and the desired new title."
    private let modelContext: ModelContext
    
    /// Requires the target conversation hash and replacement title.
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(
            properties: [
                "conversation_id": GenericLLMToolProperty(
                    type: "string",
                    description: "The hashed identifier of the conversation to rename"
                ),
                "new_title": GenericLLMToolProperty(
                    type: "string",
                    description: "The new title for the conversation"
                )
            ],
            required: ["conversation_id", "new_title"]
        )
    }
    
    /// Creates a rename tool bound to the supplied SwiftData context.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Renames the matching conversation and returns a short status message.
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
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
            
            let descriptor = FetchDescriptor<ConversationItem>()
            let conversations: [ConversationItem]
            do {
                conversations = try modelContext.fetch(descriptor)
            } catch {
                vxAtelierPro.log.error("Failed to fetch \(ConversationItem.self): \(error.localizedDescription)")
                throw AppError.dataFetchFailed(error.localizedDescription)
            }

            guard let conversation = conversations.first(where: { StableHash.md5Hex(String(describing: $0.id)) == conversationId }) else {
                return "Conversation not found"
            }
            
            let targetConversationId = conversation.id
            
            await MainActor.run {
                let descriptor = FetchDescriptor<ConversationItem>()
                if let conversation = try? modelContext.fetch(descriptor).first(where: { $0.id == targetConversationId }) {
                    conversation.title = newTitle
                }
            }
            
            return "Conversation renamed to: \(newTitle)"
        } catch let decodingError as DecodingError {
            vxAtelierPro.log.error("Failed to decode rename conversation arguments: \(decodingError.localizedDescription)")
            throw AppError.invalidArguments("Invalid argument format: \(decodingError.localizedDescription)")
        } catch {
            vxAtelierPro.log.error("Failed to rename conversation: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Executable tool that lists conversations with stable hashed IDs.
public struct ListConversationsTool: ExecutableLLMTool {
    public let name = "list_conversations"
    public let description = "Returns a JSON list of all existing chat conversations, including their unique hashed ID (for use with other conversation tools), title, and purpose."
    private let modelContext: ModelContext
    
    /// Accepts no arguments.
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(properties: [:])
    }
    
    /// Creates a listing tool bound to the supplied SwiftData context.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Returns all conversations as JSON with hashed IDs, titles, and purposes.
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let descriptor = FetchDescriptor<ConversationItem>()
        do {
            let conversations = try modelContext.fetch(descriptor)
            
            if conversations.isEmpty {
                return "No conversations found"
            }
            
            let conversationList = conversations.map { conversation -> [String: String] in
                return [
                    "id": StableHash.md5Hex(String(describing: conversation.id)),
                    "title": conversation.title,
                    "purpose": String(describing: conversation.purpose)
                ]
            }
            
            let jsonData = try JSONEncoder().encode(conversationList)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw AppError.encodingFailed("Failed to encode conversation list as UTF-8 string")
            }
            return jsonString
        } catch let error as AppError {
            vxAtelierPro.log.error("Failed to process conversations: \(error.localizedDescription)")
            throw error
        } catch {
            vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
}

/// Executable tool that finds the first conversation whose title contains a query string.
public struct FindConversationTool: ExecutableLLMTool {
    public let name = "find_conversation"
    public let description = "Finds the first chat conversation whose title contains the provided search string. Returns a JSON object with the conversation's hashed ID and full title if found, otherwise a 'not found' message."
    private let modelContext: ModelContext
    
    /// Requires the title fragment to search for.
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(
            properties: [
                "title": GenericLLMToolProperty(
                    type: "string",
                    description: "The title to search for"
                )
            ],
            required: ["title"]
        )
    }
    
    /// Creates a search tool bound to the supplied SwiftData context.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Returns the first matching conversation as JSON, or a not-found message.
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let arguments = call.argumentsJSON
        guard let jsonData = arguments.data(using: .utf8) else {
            throw AppError.invalidArguments("Failed to encode arguments as UTF-8 data")
        }
        
        do {
            let args = try JSONDecoder().decode([String: String].self, from: jsonData)
            guard let title = args["title"] else {
                throw AppError.invalidArguments("Missing required argument: title")
            }
            
            let descriptor = FetchDescriptor<ConversationItem>()
            let conversations = try modelContext.fetch(descriptor)
            
            if let conversation = conversations.first(where: { $0.title.contains(title) }) {
                let conversationInfo: [String: String] = [
                    "id": StableHash.md5Hex(String(describing: conversation.id)),
                    "title": conversation.title
                ]
                
                let jsonData = try JSONEncoder().encode(conversationInfo)
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    throw AppError.encodingFailed("Failed to encode conversation information as UTF-8 string")
                }
                return jsonString
            } else {
                return "No conversation found with title containing: \(title)"
            }
        } catch let error as DecodingError {
            vxAtelierPro.log.error("Failed to decode find conversation arguments: \(error.localizedDescription)")
            throw AppError.invalidArguments("Invalid argument format: \(error.localizedDescription)")
        } catch let error as AppError {
            vxAtelierPro.log.error("Failed to process conversation: \(error.localizedDescription)")
            throw error
        } catch {
            vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
}

/// Executable tool that reports the current conversation identity and purpose.
public struct CurrentConversationTool: ExecutableLLMTool {
    public let name = "get_current_conversation"
    public let description = "Returns a JSON object containing the unique hashed ID, title, and purpose of the chat conversation currently active in the application context."
    
    /// Accepts no arguments.
    public var parameters: any LLMToolParameters {
        GenericLLMToolParameters(properties: [:])
    }
    
    /// Creates a current-conversation tool.
    public init() {
    }
    
    /// Returns the active conversation as JSON with a stable hashed ID.
    func execute(_ call: LLMToolExecutionCall) async throws -> String {
        let conversationItem = call.context.conversation
        
        let response: [String: String] = [
            "id": StableHash.md5Hex(String(describing: conversationItem.id)),
            "title": conversationItem.title,
            "purpose": String(describing: conversationItem.purpose)
        ]
        
        do {
            let jsonData = try JSONEncoder().encode(response)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw AppError.encodingFailed("Failed to encode conversation information as UTF-8 string")
            }
            return jsonString
        } catch let error as EncodingError {
            vxAtelierPro.log.error("Failed to encode current conversation information: \(error.localizedDescription)")
            throw AppError.encodingFailed(error.localizedDescription)
        } catch {
            vxAtelierPro.log.error("Unexpected error: \(error.localizedDescription)")
            throw AppError.aiServiceError(error.localizedDescription)
        }
    }
}
