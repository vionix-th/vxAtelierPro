import Foundation
import SwiftData

struct LLMPersistenceCoordinator {
    @MainActor
    func save(_ conversation: ConversationItem) throws {
        try conversation.modelContext?.save()
    }

    @MainActor
    func removeTurn(_ turn: ConversationTurn, from conversation: ConversationItem) throws {
        if let index = conversation.turns.firstIndex(where: { $0.id == turn.id }) {
            conversation.turns.remove(at: index)
        }
        try save(conversation)
    }
}
