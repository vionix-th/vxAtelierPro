import Foundation
import SwiftData

@Model
final class ConversationTurn {    
    var sequenceNumber: Int
    var timestamp: Date

    var conversation: ConversationItem?
    var userMessage: MessageItem
    
    @Relationship(deleteRule: .cascade, inverse: \TurnEvent.turn) var events: [TurnEvent] = []
    @Relationship(deleteRule: .cascade, inverse: \BookmarkItem.turn) var bookmarks: [BookmarkItem] = []
    
    init(sequenceNumber: Int, timestamp: Date = Date(), userMessage: MessageItem, conversation: ConversationItem?) {
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.userMessage = userMessage
        self.conversation = conversation
    }
} 