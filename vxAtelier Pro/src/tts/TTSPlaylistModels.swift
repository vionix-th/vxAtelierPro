import Foundation
import SwiftData

@Model
final class TTSPlaylist {
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TTSPlaylistEntry.playlist)
    var entries: [TTSPlaylistEntry] = []

    init(name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var orderedEntries: [TTSPlaylistEntry] {
        entries.sorted { $0.orderIndex < $1.orderIndex }
    }

    func nextOrderIndex() -> Int {
        (entries.map(\.orderIndex).max() ?? -1) + 1
    }

    func normalizeEntryOrder() {
        for (index, entry) in orderedEntries.enumerated() {
            entry.orderIndex = index
        }
        updatedAt = Date()
    }
}

@Model
final class TTSPlaylistEntry {
    var orderIndex: Int
    var role: String
    var text: String
    var sourceConversationIDString: String?
    var sourceMessageIDString: String?

    var playlist: TTSPlaylist?

    init(
        orderIndex: Int,
        role: String,
        text: String,
        sourceConversationIDString: String?,
        sourceMessageIDString: String?,
        playlist: TTSPlaylist? = nil
    ) {
        self.orderIndex = orderIndex
        self.role = role
        self.text = text
        self.sourceConversationIDString = sourceConversationIDString
        self.sourceMessageIDString = sourceMessageIDString
        self.playlist = playlist
    }

    var displayText: String {
        text
    }
}
