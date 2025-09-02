import Foundation
import SwiftData

// MARK: - Prompt Template Export

struct PromptTemplateExportData: Codable {
    var name: String
    var summary: String
    var prompt: String
    var category: PromptTemplate.Category
    
    init(_ template: PromptTemplate) {
        self.name = template.name
        self.summary = template.summary
        self.prompt = template.prompt
        self.category = template.category
    }
    
    func toDataItem() -> PromptTemplate {
        return PromptTemplate(
            name: name,
            summary: summary,
            prompt: prompt,
            category: category
        )
    }
} 