import Foundation
import SwiftData
import SwiftUI

/// Represents a message in a conversation with an AI assistant.
///
/// This model stores a message along with metadata including:
/// - Role (user, assistant, system, tool)
/// - Content of the message
/// - Timestamp for conversation ordering
/// - Tool calls and responses for function calling features
@Model
final class MessageItem {
    /// The role of the message sender (user, assistant, system, tool)
    var role: String

    /// The content of the message
    @Relationship(deleteRule: .cascade) var content: ContentItem

    /// When this message was created
    var timestamp: Date

    /// Optional ID for tool responses linking back to tool calls
    var toolCallId: String?

    /// Serialized tool call data for function calling
    var toolCallsData: [Data]?

    /// Creates a new message item.
    ///
    /// - Parameters:
    ///   - role: The role of the sender (user, assistant, system, tool)
    ///   - content: The content of the message
    ///   - timestamp: When this message was created, defaults to current time
    ///   - toolCallId: Optional ID for tool responses
    ///   - toolCallsData: Serialized tool call data
    init(
        role: String,
        content: ContentItem,
        timestamp: Date = Date(),
        toolCallId: String? = nil,
        toolCallsData: [Data]? = nil
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCallId = toolCallId
        self.toolCallsData = toolCallsData
    }

    /// Stores tool calls as serialized data.
    ///
    /// - Parameter toolCalls: Array of tool calls to serialize and store
    /// - Throws: EncodingError if serialization fails
    func setToolCalls(_ toolCalls: [AIToolCall]?) {
        if let toolCalls = toolCalls {
            var encodedCalls: [Data] = []
            for toolCall in toolCalls {
                do {
                    let data = try JSONEncoder().encode(toolCall)
                    encodedCalls.append(data)
                } catch {
                    vxAtelierPro.log.error("Failed to encode tool call: \(error.localizedDescription)")
                    // Continue with other tool calls even if one fails
                }
            }
            toolCallsData = encodedCalls.isEmpty ? nil : encodedCalls
        } else {
            toolCallsData = nil
        }
    }

    /// Updates tool calls during streaming, preserving existing ones.
    ///
    /// - Parameter newToolCalls: New tool calls to add or update
    func updateToolCalls(with newToolCalls: [AIToolCall]) {
        // Create a dictionary of existing tool calls by ID for easy lookup
        var existingToolCallsDict: [String: AIToolCall] = [:]
        
        // First, load existing tool calls
        if let existingToolCalls = getToolCalls() {
            for toolCall in existingToolCalls {
                existingToolCallsDict[toolCall.id] = toolCall
            }
        }

        // Update existing tool calls or add new ones
        for newToolCall in newToolCalls {
            // Create a new dictionary for each update to ensure SwiftData tracking
            var updatedDict = existingToolCallsDict
            if let existingToolCall = updatedDict[newToolCall.id] {
                // If this tool call already exists, append the arguments
                updatedDict[newToolCall.id] = GenericToolCall(
                    id: newToolCall.id,
                    name: newToolCall.name,
                    arguments: existingToolCall.arguments + newToolCall.arguments,
                    configuration: (newToolCall as? GenericToolCall)?.configuration,
                    context: (newToolCall as? GenericToolCall)?.context
                )
            } else {
                // Otherwise add the new tool call
                updatedDict[newToolCall.id] = newToolCall
            }
            existingToolCallsDict = updatedDict
        }

        // Convert back to array and save
        let updatedToolCalls = Array(existingToolCallsDict.values)
        setToolCalls(updatedToolCalls)
    }

    /// Retrieves the deserialized tool calls from this message.
    ///
    /// - Returns: Array of tool calls, or nil if none exist
    func getToolCalls() -> [AIToolCall]? {
        guard let dataArray = toolCallsData else { return nil }
        
        var decodedCalls: [AIToolCall] = []
        for data in dataArray {
            do {
                let toolCall = try JSONDecoder().decode(GenericToolCall.self, from: data)
                decodedCalls.append(toolCall)
            } catch {
                vxAtelierPro.log.error("Failed to decode tool call: \(error.localizedDescription)")
                // Continue with other tool calls even if one fails
            }
        }
        return decodedCalls.isEmpty ? nil : decodedCalls
    }
} 
