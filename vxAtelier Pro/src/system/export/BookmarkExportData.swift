import Foundation
import SwiftData

// MARK: - Bookmark Export

struct BookmarkExportData: Codable {
    let label: String
    let turnSequence: Int
    let isEvent: Bool
    let eventIndex: Int? // Index of event in turn.events, if applicable

    init(_ bookmark: BookmarkItem) {
        self.label = bookmark.label
        self.turnSequence = bookmark.turn?.sequenceNumber ?? -1
        if let turn = bookmark.turn, let event = bookmark.target, let idx = turn.events.firstIndex(where: { $0 === event }) {
            self.isEvent = true
            self.eventIndex = idx
        } else {
            self.isEvent = false
            self.eventIndex = nil
        }
    }

    // Rehydrate: find turn by sequence, then event by index if needed
    func toDataItem(turn: ConversationTurn) -> BookmarkItem {
        if isEvent, let idx = eventIndex, idx < turn.events.count {
            return BookmarkItem(label, turn: turn, event: turn.events[idx])
        } else {
            return BookmarkItem(label, turn: turn)
        }
    }
}

