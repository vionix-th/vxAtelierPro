import SwiftData
import SwiftUI

/// Reusable prompt template list with selection and delete actions.
struct PromptTemplateListView: View {
    let category: PromptTemplate.Category?
    let selectionMode: Bool
    let selectedIDs: Set<PersistentIdentifier>
    let onSelect: (PersistentIdentifier) -> Void
    let onDeselect: (PersistentIdentifier) -> Void
    let onTemplateActivated: (PromptTemplate) -> Void
    let onDelete: ((PromptTemplate) -> Void)?

    @Query(sort: [SortDescriptor(\PromptTemplate.name)]) private var promptTemplates: [PromptTemplate]

    private var filteredTemplates: [PromptTemplate] {
        if let category {
            promptTemplates.filter { $0.category == category }
        } else {
            promptTemplates
        }
    }

    var body: some View {
        SettingsEntityList(
            items: filteredTemplates,
            emptyTitle: "No Templates",
            emptySystemImage: "text.bubble",
            emptyDescription: "Add a prompt template to reuse common prompts.",
            selectionAction: handleSelection
        ) { template in
            SettingsEntityRow(
                title: template.name,
                subtitle: template.category == .System ? "System" : "User",
                metadata: template.summary.isEmpty ? nil : template.summary,
                systemImages: selectionMode ? [selectedIDs.contains(template.id) ? "checkmark.circle.fill" : "circle"] : []
            )
        } actions: { template in
            guard !selectionMode, let onDelete else { return [] }
            return [
                SettingsEntityAction(title: "Edit", systemImage: "pencil") {
                    onTemplateActivated(template)
                },
                SettingsEntityAction(title: "Delete", systemImage: "trash", role: .destructive) {
                    onDelete(template)
                }
            ]
        }
    }

    init(
        category: PromptTemplate.Category? = nil,
        selectionMode: Bool = false,
        selectedIDs: Set<PersistentIdentifier> = [],
        onSelect: @escaping (PersistentIdentifier) -> Void = { _ in },
        onDeselect: @escaping (PersistentIdentifier) -> Void = { _ in },
        onTemplateActivated: @escaping (PromptTemplate) -> Void,
        onDelete: ((PromptTemplate) -> Void)? = nil
    ) {
        self.category = category
        self.selectionMode = selectionMode
        self.selectedIDs = selectedIDs
        self.onSelect = onSelect
        self.onDeselect = onDeselect
        self.onTemplateActivated = onTemplateActivated
        self.onDelete = onDelete
    }

    private func handleSelection(_ template: PromptTemplate) {
        if selectionMode {
            selectedIDs.contains(template.id) ? onDeselect(template.id) : onSelect(template.id)
        } else {
            onTemplateActivated(template)
        }
    }
}
