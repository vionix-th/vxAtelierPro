import SwiftUI
import SwiftData

/// A view to display and select prompt templates, often used in popovers.
struct PromptTemplateList: View {
    // Multi-select support
    let selectionMode: Bool
    let selectedIDs: Set<PersistentIdentifier>
    let onSelect: (PersistentIdentifier) -> Void
    let onDeselect: (PersistentIdentifier) -> Void

    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\PromptTemplate.name)]) private var promptTemplates: [PromptTemplate]

    let category: PromptTemplate.Category? // Optional category to filter by
    let onTemplateActivated: (PromptTemplate) -> Void // Callback when a template is chosen
    let onAddTemplate: (() -> Void)?

    @State private var editingTemplate: EditingTemplate? = nil
    @State private var showError = false
    @State private var errorMessage = ""

    struct EditingTemplate: Identifiable {
        let id = UUID()
        var template: PromptTemplate
        var isNew: Bool
    }

    private var filteredTemplates: [PromptTemplate] {
        if let category = category {
            return promptTemplates.filter { $0.category == category }
        } else {
            // If no category specified, maybe show all? Or adjust as needed.
            // For now, showing all if category is nil.
            return promptTemplates
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            if filteredTemplates.isEmpty {
                Text("No templates available.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(filteredTemplates) { template in
                        let isSelected = selectedIDs.contains(template.id)
                        SettingsListRow(
                            title: template.name,
                            subtitle: template.category == .System ? "System" : "User",
                            icons: [],
                            selectionEnabled: selectionMode,
                            selected: isSelected,
                            onEdit: {
                                editingTemplate = EditingTemplate(template: template, isNew: false)
                            },
                            onDelete: {
                                vxAtelierPro.log.notice("Deleting template '\(template.name)'")
                                do {
                                    try queryManager.delete(template)
                                } catch {
                                    vxAtelierPro.log.error("Failed to delete template '\(template.name)': \(error.localizedDescription)")
                                    errorMessage = "Failed to delete template: \(error.localizedDescription)"
                                    showError = true
                                }
                            }
                        ) {
                            if !template.summary.isEmpty {
                                Text(template.summary)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectionMode {
                                isSelected ? onDeselect(template.id) : onSelect(template.id)
                            } else {
                                onTemplateActivated(template)
                            }
                        }
                        .settingsRowActions(
                            onEdit: {
                                editingTemplate = EditingTemplate(template: template, isNew: false)
                            },
                            onDelete: {
                                vxAtelierPro.log.notice("Deleting template '\(template.name)'")
                                do {
                                    try queryManager.delete(template)
                                } catch {
                                    vxAtelierPro.log.error("Failed to delete template '\(template.name)': \(error.localizedDescription)")
                                    errorMessage = "Failed to delete template: \(error.localizedDescription)"
                                    showError = true
                                }
                            }
                        )
                    }
                }
            }
        }
        // Sizing is now the responsibility of the parent view. This view relies on SwiftUI's natural sizing.
        .sheet(item: $editingTemplate) { editing in
            NavigationStack {
                PromptTemplateEditView(
                    template: editing.template,
                    isNewTemplate: editing.isNew,
                    templates: promptTemplates,
                    onComplete: { success in
                        if success {
                            do {
                                if editing.isNew {
                                    try queryManager.insert(editing.template)
                                    vxAtelierPro.log.notice("Added new template '\(editing.template.name)'")
                                } else {
                                    try queryManager.saveContext()
                                    vxAtelierPro.log.notice("Updated template '\(editing.template.name)'")
                                }
                            } catch {
                                vxAtelierPro.log.error("Failed to save template '\(editing.template.name)': \(error.localizedDescription)")
                                errorMessage = "Failed to save template: \(error.localizedDescription)"
                                showError = true
                            }
                        }
                        editingTemplate = nil
                    }
                )
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // Initializer allowing nil category and optional add action
    init(
        category: PromptTemplate.Category? = nil,
        selectionMode: Bool = false,
        selectedIDs: Set<PersistentIdentifier> = [],
        onSelect: @escaping (PersistentIdentifier) -> Void = { _ in },
        onDeselect: @escaping (PersistentIdentifier) -> Void = { _ in },
        onTemplateActivated: @escaping (PromptTemplate) -> Void,
        onAddTemplate: (() -> Void)? = nil
    ) {
        self.category = category
        self.selectionMode = selectionMode
        self.selectedIDs = selectedIDs
        self.onSelect = onSelect
        self.onDeselect = onDeselect
        self.onTemplateActivated = onTemplateActivated
        self.onAddTemplate = onAddTemplate
    }
}
