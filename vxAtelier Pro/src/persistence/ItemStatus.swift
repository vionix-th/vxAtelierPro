import Foundation

/// Status categories for items in the application.
/// Used by both ConversationItem and ProjectItem to track their lifecycle state.
public enum ItemStatus: String, Codable {
    /// Active and visible item
    case active = "active"

    /// Archived item (hidden but preserved)
    case archived = "archived"

    /// Trashed item (pending deletion)
    case trashed = "trashed"
}
