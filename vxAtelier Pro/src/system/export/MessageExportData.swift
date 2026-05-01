import Foundation
import SwiftData

// MARK: - Message Export

struct MessageExportData: Codable {
    let role: String
    let contentParts: [MessageContentPartExportData]
    let timestamp: Date
    let toolCallId: String?
    let toolCalls: [ToolCallExportData]
    
    init(_ message: MessageItem) {
        self.role = message.role
        self.contentParts = message.orderedContentParts.map { MessageContentPartExportData($0) }
        self.timestamp = message.timestamp
        self.toolCallId = message.toolCallId
        self.toolCalls = message.orderedToolCallItems.map { ToolCallExportData($0) }
    }
    
    func toDataItem() -> MessageItem {
        MessageItem(
            role: role,
            contentParts: contentParts.map { $0.toDataItem() },
            timestamp: timestamp,
            toolCallId: toolCallId,
            toolCalls: toolCalls.map { $0.toDataItem() }
        )
    }
}

struct MessageContentPartExportData: Codable {
    let index: Int
    let kindRaw: String
    let text: String?
    let mimeType: String?
    let dataBase64: String?
    let sourceURL: String?

    init(_ item: MessageContentPartItem) {
        self.index = item.index
        self.kindRaw = item.kindRaw
        self.text = item.text
        self.mimeType = item.mimeType
        self.dataBase64 = item.dataBase64
        self.sourceURL = item.sourceURL
    }

    func toDataItem() -> MessageContentPartItem {
        MessageContentPartItem(
            index: index,
            kind: LLMContentPart.Kind(rawValue: kindRaw) ?? .text,
            text: text,
            mimeType: mimeType,
            dataBase64: dataBase64,
            sourceURL: sourceURL
        )
    }
}

struct ToolCallExportData: Codable {
    let callID: String
    let providerCallID: String?
    let index: Int
    let name: String
    let argumentsJSON: String
    let statusRaw: String
    let errorMessage: String?

    init(_ item: ToolCallItem) {
        self.callID = item.callID
        self.providerCallID = item.providerCallID
        self.index = item.index
        self.name = item.name
        self.argumentsJSON = item.argumentsJSON
        self.statusRaw = item.statusRaw
        self.errorMessage = item.errorMessage
    }

    func toDataItem() -> ToolCallItem {
        let item = ToolCallItem(
            callID: callID,
            providerCallID: providerCallID,
            index: index,
            name: name,
            argumentsJSON: argumentsJSON,
            status: LLMToolCallStatus(rawValue: statusRaw) ?? .readyToExecute
        )
        item.errorMessage = errorMessage
        return item
    }
}
