import Foundation
import SwiftData
import SwiftUI

/// Represents a content item containing text data of a specific type.
///
/// Used to store the actual content for messages in conversations,
/// separating the content from its metadata.
@Model
final class ContentItem {
    /// The text content itself
    var text: String

    /// The type of content (e.g., "Text", "Code", "Markdown")
    var type: String

    /// Creates a new content item.
    ///
    /// - Parameters:
    ///   - text: The text content
    ///   - type: The content type, defaults to "Text"
    init(_ text: String, type: String = "Text") {
        self.text = text
        self.type = type
    }
} 