import Foundation
import SwiftData
import SwiftUI

/// A shared component to process AI chat completions, both in streaming and non-streaming modes.
/// For streaming completions, it accumulates content and merges tool calls using a common logic to ensure tool parameters are merged correctly.
struct CompletionStreamProcessor {
    
    /// Processes a streaming completion, accumulating content and merging any tool calls received over streamed chunks.
    /// - Parameters:
    ///   - service: The AI service providing the stream.
    ///   - request: The configured AIChatCompletionRequest to be sent.
    ///   - updateHandler: An optional closure to update the UI (e.g. streaming state text) with the accumulated content.
    /// - Returns: A GenericChatCompletionResponse with the full accumulated content and merged tool calls.
    static func processStream(
        service: AIService,
        request: AIChatCompletionRequest,
        updateHandler: ((String) -> Void)? = nil
    ) async throws -> GenericChatCompletionResponse {
        var accumulatedContent = ""
        var accumulatedToolCalls: [AIToolCall]? = nil
        
        // Process each chunk from the streaming response
        for try await chunk in service.chat.completeStream(request: request) {
            if let content = chunk.content {
                accumulatedContent += content
                updateHandler?(accumulatedContent)
            }
            if let toolCalls = chunk.toolCalls, !toolCalls.isEmpty {
                if let existing = accumulatedToolCalls {
                    accumulatedToolCalls = mergeToolCalls(existing: existing, new: toolCalls)
                } else {
                    accumulatedToolCalls = toolCalls
                }
            }
            if chunk.isFinal {
                // Once final chunk is reached, break out of the loop
                break
            }
        }

        return GenericChatCompletionResponse(content: accumulatedContent, toolCalls: accumulatedToolCalls)
    }

    /// Merges incoming tool calls with an existing list, ensuring that tool calls with the same id have their arguments concatenated.
    /// - Parameters:
    ///   - existing: The existing accumulated tool calls.
    ///   - new: The new tool calls received from the latest chunk.
    /// - Returns: A merged array of AIToolCall values.
    static func mergeToolCalls(existing: [AIToolCall], new newToolCalls: [AIToolCall]) -> [AIToolCall] {
        var merged = existing
        for newTool in newToolCalls {
            if let index = merged.firstIndex(where: { $0.id == newTool.id }) {
                let mergedArguments = merged[index].arguments + newTool.arguments
                merged[index] = GenericToolCall(
                    id: newTool.id,
                    name: newTool.name,
                    arguments: mergedArguments,
                    configuration: newTool.configuration,
                    context: newTool.context
                )
            } else {
                merged.append(newTool)
            }
        }
        return merged
    }
} 