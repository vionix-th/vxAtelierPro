import Foundation
import SwiftData
import SwiftUI

@Model
final class MessageItem {
    var role: String

    @Relationship(deleteRule: .cascade) var contentParts: [MessageContentPartItem] = []
    @Relationship(deleteRule: .cascade, inverse: \ToolCallItem.assistantMessage) var toolCallItems: [ToolCallItem] = []

    var timestamp: Date

    var toolCallId: String?

    var displayText: String {
        orderedContentParts.compactMap(\.text).joined()
    }

    var orderedContentParts: [MessageContentPartItem] {
        contentParts.sorted { $0.index < $1.index }
    }

    var orderedToolCallItems: [ToolCallItem] {
        toolCallItems.sorted { $0.index < $1.index }
    }

    init(
        role: String,
        contentParts: [MessageContentPartItem],
        timestamp: Date = Date(),
        toolCallId: String? = nil,
        toolCalls: [ToolCallItem] = []
    ) {
        self.role = role
        self.contentParts = contentParts
        self.timestamp = timestamp
        self.toolCallId = toolCallId
        self.toolCallItems = toolCalls
    }

    convenience init(
        role: String,
        text: String,
        kind: LLMContentPart.Kind = .text,
        timestamp: Date = Date(),
        toolCallId: String? = nil,
        toolCalls: [ToolCallItem] = []
    ) {
        self.init(
            role: role,
            contentParts: [MessageContentPartItem(index: 0, kind: kind, text: text)],
            timestamp: timestamp,
            toolCallId: toolCallId,
            toolCalls: toolCalls
        )
    }

    func setContentParts(_ parts: [MessageContentPartItem]) {
        contentParts = parts.enumerated().map { offset, part in
            part.index = offset
            return part
        }
    }

    func asDomainMessage() -> LLMMessage {
        LLMMessage(
            role: role,
            content: orderedContentParts.map { $0.asDomainPart() },
            toolCalls: orderedToolCallItems.map { $0.asDomainToolCall() },
            toolCallID: toolCallId
        )
    }

    func setToolCalls(_ toolCalls: [LLMToolCall]) {
        toolCallItems = toolCalls.enumerated().map { offset, toolCall in
            ToolCallItem(
                callID: toolCall.id,
                providerCallID: toolCall.callID,
                index: toolCall.index == 0 ? offset : toolCall.index,
                name: toolCall.name,
                argumentsJSON: toolCall.argumentsJSON,
                status: .readyToExecute,
                assistantMessage: self
            )
        }
    }

    func updateToolCalls(with newToolCalls: [LLMToolCall]) {
        for newToolCall in newToolCalls {
            if let existing = toolCallItems.first(where: { $0.callID == newToolCall.id }) {
                if !newToolCall.name.isEmpty {
                    existing.name = newToolCall.name
                }
                existing.argumentsJSON += newToolCall.argumentsJSON
            } else {
                let nextIndex = (toolCallItems.map(\.index).max() ?? -1) + 1
                toolCallItems.append(
                    ToolCallItem(
                        callID: newToolCall.id,
                        providerCallID: newToolCall.callID,
                        index: nextIndex,
                        name: newToolCall.name,
                        argumentsJSON: newToolCall.argumentsJSON,
                        status: .readyToExecute,
                        assistantMessage: self
                    )
                )
            }
        }
    }
}
