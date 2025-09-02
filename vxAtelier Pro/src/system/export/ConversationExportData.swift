import Foundation
import SwiftData

// MARK: - Dialog Export

struct ConversationExportData: Codable {
    private enum CodingKeys: String, CodingKey {
        case timestamp, title, turns, options, status, purpose, tokenCount, usedTokenCount
    }

    let timestamp: Date
    let title: String
    let turns: [TurnExportData]
    let options: ConversationOptionsExportData
    let status: String
    let purpose: String
    let tokenCount: Int
    let usedTokenCount: Int
    
    init(_ dialog: ConversationItem) {
        self.timestamp = dialog.timestamp
        self.title = dialog.title
        self.turns = dialog.turns.map { TurnExportData($0) }
        self.options = ConversationOptionsExportData(dialog.options)
        self.status = dialog.status.rawValue
        self.purpose = dialog.purpose.rawValue
        self.tokenCount = dialog.tokenCount
        self.usedTokenCount = dialog.usedTokenCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        title = try container.decode(String.self, forKey: .title)
        turns = try container.decode([TurnExportData].self, forKey: .turns)
        options = try container.decode(ConversationOptionsExportData.self, forKey: .options)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ItemStatus.active.rawValue
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? ConversationItem.DialogPurpose.user.rawValue
        tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount) ?? 0
        usedTokenCount = try container.decodeIfPresent(Int.self, forKey: .usedTokenCount) ?? 0
    }
    
    func toDataItem(context: ModelContext) throws -> ConversationItem {
        let dialog = ConversationItem(title)
        dialog.timestamp = timestamp
        dialog.options = options.toDataItem(context: context)
        dialog.status = ItemStatus(rawValue: status) ?? ItemStatus.active
        dialog.purpose = ConversationItem.DialogPurpose(rawValue: purpose) ?? .user
        dialog.tokenCount = tokenCount
        dialog.usedTokenCount = usedTokenCount
        for turnData in turns {
            let turn = try turnData.toDataItem(context: context, conversation: dialog)
            dialog.turns.append(turn)
        }
        return dialog
    }
}

struct TurnExportData: Codable {
    private enum CodingKeys: String, CodingKey {
        case sequenceNumber, timestamp, userMessage, events
    }

    let sequenceNumber: Int
    let timestamp: Date
    let userMessage: MessageExportData
    let events: [TurnEventExportData]
    
    init(_ turn: ConversationTurn) {
        self.sequenceNumber = turn.sequenceNumber
        self.timestamp = turn.timestamp
        self.userMessage = MessageExportData(turn.userMessage)
        self.events = turn.events.map { TurnEventExportData($0) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequenceNumber = try container.decode(Int.self, forKey: .sequenceNumber)
        userMessage = try container.decode(MessageExportData.self, forKey: .userMessage)
        events = try container.decode([TurnEventExportData].self, forKey: .events)
        // For backward compatibility, if timestamp is missing, use the user message's timestamp.
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? userMessage.timestamp
    }
    
    func toDataItem(context: ModelContext, conversation: ConversationItem) throws -> ConversationTurn {
        let userMsg = userMessage.toDataItem()
        let turn = ConversationTurn(
            sequenceNumber: self.sequenceNumber,
            timestamp: timestamp,
            userMessage: userMsg,
            conversation: conversation
        )
        turn.events = events.map { $0.toDataItem(turn: turn) }
        return turn
    }
}

struct TurnEventExportData: Codable {
    let type: String
    let timestamp: Date
    let message: MessageExportData

    init(_ event: TurnEvent) {
        self.type = event.type.rawValue
        self.timestamp = event.timestamp
        self.message = MessageExportData(event.message)
    }

    func toDataItem(turn: ConversationTurn) -> TurnEvent {
        let eventType = TurnEvent.EventType(rawValue: type) ?? .assistant
        let msg = message.toDataItem()
        return TurnEvent(type: eventType, timestamp: self.timestamp, message: msg, turn: turn)
    }
} 
