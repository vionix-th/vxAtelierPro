import Foundation
import SwiftUI
import SwiftData

/// Caches one ConversationViewModel per conversation ID so UI state
/// (scroll position, selection, streaming flags) persists while the
/// user navigates between conversations.
@Observable
@MainActor
final class ConversationViewModelStore {
    private let queryManager: QueryManager
    private let ttsQueue: TTSQueue
    private var cache: [PersistentIdentifier: ConversationViewModel] = [:]

    init(queryManager: QueryManager, ttsQueue: TTSQueue) {
        self.queryManager = queryManager
        self.ttsQueue = ttsQueue
    }

    func viewModel(for id: PersistentIdentifier) -> ConversationViewModel {
        if let existing = cache[id] {
            return existing
        }

        let viewModel = ConversationViewModel(
            conversationID: id,
            queryManager: queryManager,
            ttsQueue: ttsQueue
        )
        cache[id] = viewModel
        return viewModel
    }

    func remove(_ id: PersistentIdentifier) {
        cache[id] = nil
    }
}
