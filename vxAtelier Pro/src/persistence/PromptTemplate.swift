import Foundation
import SwiftData
import SwiftUI

/// Represents a template for system or user prompts.
///
/// Templates provide reusable prompt content that can be quickly
/// applied to new conversations.
@Model
final class PromptTemplate {
    /// Categories for different prompt templates
    enum Category: Int, Codable {
        /// User message template
        case User

        /// System instruction template
        case System
    }

    /// Display name of the template
    var name: String

    /// Brief description of the template's purpose
    var summary: String

    /// The actual prompt content
    var prompt: String

    /// Category this template belongs to
    var category: Category

    /// Creates a new prompt template.
    ///
    /// - Parameters:
    ///   - name: Display name of the template
    ///   - summary: Brief description of the template's purpose
    ///   - prompt: The actual prompt content
    ///   - category: Category this template belongs to
    init(name: String, summary: String = "", prompt: String = "", category: Category = .User) {
        self.name = name
        self.summary = summary
        self.prompt = prompt
        self.category = category
    }
} 