import Foundation
import SwiftData

@Model
final class TurnEvent {
    enum EventType: String, Codable {
        case assistant
        case toolCall
        case toolResult
    }
    var type: EventType
    var timestamp: Date
    var message: MessageItem
    var turn: ConversationTurn?
    
    init(type: EventType, timestamp: Date = Date(), message: MessageItem, turn: ConversationTurn?) {
        self.type = type
        self.timestamp = timestamp
        self.message = message
        self.turn = turn
    }
} 