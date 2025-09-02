import SwiftUI
import SwiftData
import Foundation

/// Handles streaming updates for a dialog, updating the UI in real-time
public class StreamingConversationHandler {
    private let dialog: ConversationItem
    private let queryManager: QueryManager
    private var currentMessage: MessageItem?
    private let streamingState: StreamingState
    private var receivedToolCalls: Bool = false
    private let errorStream: AsyncStream<Error>
    private let errorContinuation: AsyncStream<Error>.Continuation
    
    init(dialog: ConversationItem, queryManager: QueryManager, streamingState: StreamingState) {
        self.dialog = dialog
        self.queryManager = queryManager
        self.streamingState = streamingState
        
        // Create error stream
        var continuation: AsyncStream<Error>.Continuation!
        self.errorStream = AsyncStream { continuation = $0 }
        self.errorContinuation = continuation
    }
    
    public var errors: AsyncStream<Error> {
        errorStream
    }
    
    private func reportError(_ error: Error) {
        errorContinuation.yield(error)
    }
    
    public func onChunk(content: String?, toolCalls: [AIToolCall]?) {
        Task { @MainActor in
            // Update streaming state for immediate UI feedback
            if let content = content, !content.isEmpty {
                if !streamingState.isActive {
                    streamingState.isActive = true
                }
                streamingState.appendContent(content)
            }
            
            // Handle tool calls
            if let toolCalls = toolCalls as? [GenericToolCall], !toolCalls.isEmpty {
                receivedToolCalls = true
                streamingState.isActive = true
                streamingState.updateToolCalls(toolCalls)
            }
            
            // Prepare the message object (not added to dialog yet)
            if currentMessage == nil {
                // Create a new message object that will be added when streaming completes
                currentMessage = MessageItem(
                    role: "assistant",
                    content: ContentItem(content ?? ""),
                    timestamp: Date(),
                    toolCallId: nil,
                    toolCallsData: nil
                )
            } else if let content = content, !content.isEmpty {
                // Update the message content
                currentMessage?.content.text += content
            }
            
            // Update tool calls if present
            if let toolCalls = toolCalls as? [GenericToolCall], !toolCalls.isEmpty {
                currentMessage?.updateToolCalls(with: toolCalls)
            }
        }
    }
    
    public func onComplete() {
        Task { @MainActor in
            // Add the completed message to the dialog
            if let message = currentMessage {
                if message.role == "assistant" {
                    if let lastTurn = dialog.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) {
                        let event = TurnEvent(type: .assistant, timestamp: message.timestamp, message: message, turn: lastTurn)
                        lastTurn.events.append(event)
                    }
                } else if message.role == "tool" {
                    if let lastTurn = dialog.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) {
                        let event = TurnEvent(type: .toolResult, timestamp: message.timestamp, message: message, turn: lastTurn)
                        lastTurn.events.append(event)
                    }
                }
                dialog.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: true)
                
                // If we received tool calls, we need to handle them
                if receivedToolCalls, let toolCalls = message.getToolCalls(), !toolCalls.isEmpty {
                    vxAtelierPro.log.debug("Handling \(toolCalls.count) tool calls from streaming response")
                    do {
                        let configuredToolCalls = try toolCalls.map { toolCall -> AIToolCall in
                            guard let toolName = toolCall.name as String? else {
                                throw AIServiceError.unsupportedOperation("Tool call has invalid name")
                            }
                            let toolConfig = dialog.options.getToolConfiguration(toolName)
                            guard dialog.options.isToolEnabled(toolName) else {
                                throw AIServiceError.unsupportedOperation(
                                    "Tool '\(toolName)' is not enabled for this dialog")
                            }
                            return GenericToolCall(
                                id: toolCall.id,
                                name: toolCall.name,
                                arguments: toolCall.arguments,
                                configuration: toolConfig,
                                context: dialog
                            )
                        }
                        let toolResults = try await DefaultToolHandler().handleToolCalls(configuredToolCalls)
                        if let lastTurn = dialog.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) {
                            // Anchor tool result timestamps to the assistant message timestamp for deterministic ordering
                            let baseTimestamp = message.timestamp
                            for (idx, result) in toolResults.enumerated() {
                                let ts = baseTimestamp.addingTimeInterval(0.001 * Double(idx + 1))
                                let toolMsg = MessageItem(
                                    role: "tool",
                                    content: ContentItem(result.output),
                                    timestamp: ts,
                                    toolCallId: result.toolCallId,
                                    toolCallsData: nil
                                )
                                let event = TurnEvent(type: .toolResult, timestamp: toolMsg.timestamp, message: toolMsg, turn: lastTurn)
                                lastTurn.events.append(event)
                            }
                        }
                    } catch {
                        vxAtelierPro.log.error("Error handling tool calls: \(error.localizedDescription)")
                        reportError(error)
                        return
                    }
                }
                do {
                    try queryManager.saveContext()
                } catch {
                    vxAtelierPro.log.error("Failed to save dialog changes: \(error.localizedDescription)")
                    reportError(error)
                    return
                }
            }
            streamingState.reset()
            vxAtelierPro.log.debug("Completed streaming")
            // Clear current message to avoid reusing it on the next stream
            self.currentMessage = nil
            self.receivedToolCalls = false
        }
    }
    
    public func onError(_ error: Error) {
        Task { @MainActor in
            // Reset streaming state
            streamingState.reset()
            
            // No need to remove message from dialog as it was never added
            currentMessage = nil
            
            vxAtelierPro.log.error("Error during streaming - \(error.localizedDescription)")
            reportError(error)
        }
    }
    
    deinit {
        errorContinuation.finish()
    }
} 
