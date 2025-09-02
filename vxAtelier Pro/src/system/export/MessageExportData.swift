import Foundation
import SwiftData

// MARK: - Message Export

struct MessageExportData: Codable {
    let role: String
    let content: String?
    let contentType: String
    let timestamp: Date
    let toolCallId: String?
    let toolCallsData: [Data]?
    
    init(_ message: MessageItem) {
        self.role = message.role
        self.content = message.content.text
        self.contentType = message.content.type
        self.timestamp = message.timestamp
        self.toolCallId = message.toolCallId
        self.toolCallsData = message.toolCallsData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        contentType = try container.decode(String.self, forKey: .contentType)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        toolCallsData = try container.decodeIfPresent([Data].self, forKey: .toolCallsData)
    }
    
    func toDataItem() -> MessageItem {
        let content = ContentItem(self.content ?? "", type: self.contentType)
        return MessageItem(
            role: role,
            content: content,
            timestamp: timestamp,
            toolCallId: toolCallId,
            toolCallsData: toolCallsData
        )
    }
} 