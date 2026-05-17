import Foundation
import SwiftData

struct TTSPlaylistExportData: Codable {
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let entries: [TTSPlaylistEntryExportData]

    init(_ playlist: TTSPlaylist) {
        self.name = playlist.name
        self.createdAt = playlist.createdAt
        self.updatedAt = playlist.updatedAt
        self.entries = playlist.orderedEntries.map { TTSPlaylistEntryExportData($0) }
    }

    func toDataItem() -> TTSPlaylist {
        let playlist = TTSPlaylist(name: name, createdAt: createdAt, updatedAt: updatedAt)
        playlist.entries = entries.enumerated().map { index, entry in
            entry.toDataItem(orderIndex: index, playlist: playlist)
        }
        return playlist
    }
}

struct TTSPlaylistEntryExportData: Codable {
    let role: String
    let text: String
    let sourceConversationIDString: String?
    let sourceMessageIDString: String?

    init(_ entry: TTSPlaylistEntry) {
        self.role = entry.role
        self.text = entry.text
        self.sourceConversationIDString = entry.sourceConversationIDString
        self.sourceMessageIDString = entry.sourceMessageIDString
    }

    func toDataItem(orderIndex: Int, playlist: TTSPlaylist) -> TTSPlaylistEntry {
        TTSPlaylistEntry(
            orderIndex: orderIndex,
            role: role,
            text: text,
            sourceConversationIDString: sourceConversationIDString,
            sourceMessageIDString: sourceMessageIDString,
            playlist: playlist
        )
    }
}
