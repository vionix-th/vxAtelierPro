import Foundation
import SwiftData
import SwiftUI

/// Represents a project containing multiple dialog conversations.
///
/// Projects help organize related conversations and provide default
/// settings that are shared across all dialogs in the project.
@Model
final class ProjectItem {
    /// Display name of the project
    var name: String

    /// Creation timestamp for the project
    var timestamp: Date

    /// Default options for dialogs created in this project
    @Relationship(deleteRule: .cascade) var defaultOptions: ConversationOptions

    /// Dialogs belonging to this project
    @Relationship(deleteRule: .cascade, inverse: \ConversationItem.project) var conversations: [ConversationItem] = []

    /// Current status of this project (active, archived, trashed)
    var status: ItemStatus = ItemStatus.active

    /// Active dialogs in this project, sorted by timestamp
    @Transient var sortedDialogs: [ConversationItem] {
        return
            conversations
            .filter { $0.status == ItemStatus.active }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Creates a new project with the specified name and options.
    ///
    /// - Parameters:
    ///   - name: Display name of the project
    ///   - defaultOptions: Default options for dialogs in this project
    ///   - status: Initial status of the project
    ///   - timestamp: Creation date (optional, defaults to now)
    init(
        _ name: String, defaultOptions: ConversationOptions = ConversationOptions(),
        status: ItemStatus = ItemStatus.active,
        timestamp: Date = Date()
    ) {
        self.name = name
        self.defaultOptions = defaultOptions
        self.status = status
        self.timestamp = timestamp
    }
} 
