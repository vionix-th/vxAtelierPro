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
    private var lru: [PersistentIdentifier] = []
    private let maxCacheSize = 8

    init(queryManager: QueryManager, ttsQueue: TTSQueue) {
        self.queryManager = queryManager
        self.ttsQueue = ttsQueue
    }

    func viewModel(for id: PersistentIdentifier) -> ConversationViewModel {
        if let existing = cache[id] {
            bumpLRU(id)
            return existing
        }

        let viewModel = ConversationViewModel(
            conversationID: id,
            queryManager: queryManager,
            ttsQueue: ttsQueue
        )
        cache[id] = viewModel
        bumpLRU(id)
        evictIfNeeded()
        return viewModel
    }

    func remove(_ id: PersistentIdentifier) {
        cache[id] = nil
        lru.removeAll(where: { $0 == id })
    }
    
    func prune(toExisting ids: Set<PersistentIdentifier>) {
        let stale = cache.keys.filter { !ids.contains($0) }
        stale.forEach { remove($0) }
    }

    private func bumpLRU(_ id: PersistentIdentifier) {
        lru.removeAll(where: { $0 == id })
        lru.insert(id, at: 0)
    }

    private func evictIfNeeded() {
        while lru.count > maxCacheSize {
            if let last = lru.popLast() {
                cache[last] = nil
            }
        }
    }
}
