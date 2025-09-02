import Foundation
import SwiftData
import SwiftUI

/// Represents a bookmark to a specific message in a conversation.
///
/// Bookmarks provide quick access to important messages within dialogs,
/// allowing users to save and recall significant points in a conversation.
@Model
final class BookmarkItem {
    /// Display label for this bookmark
    var label: String

    /// Parent turn to which this bookmark belongs
    var turn: ConversationTurn?

    /// Optional target event. If nil, the bookmark refers to the user message of the turn.
    var target: TurnEvent?

    /// Transient cache of the target message ID for safe render-loop checks.
    /// This avoids dereferencing `target?.message` during SwiftUI updates when the
    /// underlying event may have been deleted but the optional relationship has not yet been nulled.
    /// Not persisted.
    @Transient
    var targetMessageIDCache: PersistentIdentifier? = nil

    /// Creates a new bookmark for the user message of a turn.
    /// - Parameters:
    ///   - label: Display label for this bookmark
    ///   - turn: The ConversationTurn containing the message
    init(_ label: String, turn: ConversationTurn?) {
        self.label = label
        self.turn = turn
        self.target = nil
    }

    /// Creates a new bookmark for a specific event within a turn.
    /// - Parameters:
    ///   - label: Display label for this bookmark
    ///   - turn: The ConversationTurn containing the event
    ///   - event: The TurnEvent to bookmark
    init(_ label: String, turn: ConversationTurn?, event: TurnEvent) {
        self.label = label
        self.turn = turn
        self.target = event
        // Initialize transient cache for safe lookups
        self.targetMessageIDCache = event.message.id
    }
}

