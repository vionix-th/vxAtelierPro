import SwiftData
import SwiftUI

/// Prompt template management and import/export controls.
struct PromptsSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\PromptTemplate.name)]) private var promptTemplates: [PromptTemplate]
    @State private var editingTemplate: EditingTemplate?
    @State private var showPromptTemplateError = false
    @State private var promptTemplateErrorMessage = ""
    @State private var selectionMode = false
    @State private var selectedTemplateIDs: Set<PersistentIdentifier> = []
    @State private var isExporting = false
    @State private var exportDocument: PromptExportDocument?
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var confirmation: SettingsConfirmation?

    /// In-memory state for a prompt template being edited.
    struct EditingTemplate: Identifiable {
        let id = UUID()
        var templateID: PersistentIdentifier?
        var draft: PromptTemplateDraft
        var isNew: Bool
    }

    private var allSelected: Bool {
        !promptTemplates.isEmpty && selectedTemplateIDs.count == promptTemplates.count
    }

    var body: some View {
        SettingsListPage(title: "Prompts") {
            VStack(spacing: AppDefaults.paddingLarge) {
                SettingsPageActionRegion {
                    addTemplateButton
                    importButton
                    exportButton
                    selectAllButton
                    if selectionMode {
                        cancelExportButton
                    }
                }

                PromptTemplateListView(
                    selectionMode: selectionMode,
                    selectedIDs: selectedTemplateIDs,
                    onSelect: { selectedTemplateIDs.insert($0) },
                    onDeselect: { selectedTemplateIDs.remove($0) },
                    onTemplateActivated: { templateID in
                        guard let template = queryManager.promptTemplate(with: templateID) else { return }
                        editingTemplate = EditingTemplate(
                            templateID: template.id,
                            draft: PromptTemplateDraft(
                                name: template.name,
                                category: template.category,
                                summary: template.summary,
                                prompt: template.prompt
                            ),
                            isNew: false
                        )
                    },
                    onDelete: confirmDeleteTemplate
                )
            }
        }
        .settingsNavigationActions {
            addTemplateButton
            importButton
            exportButton
            selectAllButton
        } cancellation: {
            Group {
                if selectionMode {
                    cancelExportButton
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "vxAtelier-Pro-Prompts.json"
        ) { result in
            switch result {
            case .success(let url):
                vxAtelierPro.log.log("Successfully exported prompts to \(url.path)")
            case .failure(let error):
                vxAtelierPro.log.error("Failed to export prompts: \(error.localizedDescription)")
            }
            selectionMode = false
            selectedTemplateIDs.removeAll()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                importPrompts(from: url)
            case .failure(let error):
                importMessage = "Failed to select file: \(error.localizedDescription)"
                showImportAlert = true
            }
        }
        .alert("Import Complete", isPresented: $showImportAlert, presenting: importMessage) { _ in
            Button("OK") { }
        } message: { message in
            Text(message)
        }
        .sheet(item: $editingTemplate) { editing in
            NavigationStack {
                PromptTemplateEditView(
                    templateID: editing.templateID,
                    draft: editing.draft,
                    isNewTemplate: editing.isNew,
                    existingTemplates: promptTemplates.map { PromptTemplateIdentity(id: $0.id, name: $0.name) },
                    onCancel: {
                        editingTemplate = nil
                    },
                    onSave: { templateID, draft in
                        saveTemplate(templateID: templateID, draft: draft)
                    }
                )
            }
        }
        .alert("Template Error", isPresented: $showPromptTemplateError) {
            Button("OK") { showPromptTemplateError = false }
        } message: {
            Text(promptTemplateErrorMessage)
        }
        .settingsConfirmationDialog($confirmation)
    }

    private var addTemplateButton: some View {
        Button {
            addTemplate()
        } label: {
            Label("Add Template", systemImage: "plus")
        }
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .disabled(selectionMode)
    }

    private var exportButton: some View {
        Button {
            if selectionMode {
                exportSelectedTemplates()
            } else {
                selectionMode = true
            }
        } label: {
            Label(selectionMode ? "Export Selected" : "Export", systemImage: "square.and.arrow.up")
        }
        .disabled(selectionMode && selectedTemplateIDs.isEmpty)
    }

    private var selectAllButton: some View {
        Button {
            if allSelected {
                selectedTemplateIDs.removeAll()
            } else {
                selectedTemplateIDs = Set(promptTemplates.map(\.id))
            }
        } label: {
            Label(allSelected ? "Select None" : "Select All", systemImage: allSelected ? "circle" : "checkmark.circle")
        }
        .disabled(!selectionMode || promptTemplates.isEmpty)
    }

    private var cancelExportButton: some View {
        Button("Cancel Export") {
            selectionMode = false
            selectedTemplateIDs.removeAll()
        }
    }

    private func addTemplate() {
        editingTemplate = EditingTemplate(
            templateID: nil,
            draft: PromptTemplateDraft(name: "New Template", category: .User, summary: "", prompt: ""),
            isNew: true
        )
    }

    private func saveTemplate(templateID: PersistentIdentifier?, draft: PromptTemplateDraft) -> String? {
        do {
            if let templateID, let template = queryManager.promptTemplate(with: templateID) {
                template.name = draft.name
                template.category = draft.category
                template.summary = draft.summary
                template.prompt = draft.prompt
                try queryManager.saveContext()
            } else {
                let template = PromptTemplate(
                    name: draft.name,
                    summary: draft.summary,
                    prompt: draft.prompt,
                    category: draft.category
                )
                try queryManager.insert(template)
            }
            return nil
        } catch {
            return "Failed to save template: \(error.localizedDescription)"
        }
    }

    private func deleteTemplate(id: PersistentIdentifier) {
        do {
            guard let template = queryManager.promptTemplate(with: id) else { return }
            try queryManager.delete(template)
        } catch {
            promptTemplateErrorMessage = "Failed to delete template: \(error.localizedDescription)"
            showPromptTemplateError = true
        }
    }

    private func confirmDeleteTemplate(_ templateID: PersistentIdentifier) {
        guard let template = queryManager.promptTemplate(with: templateID) else { return }
        confirmation = SettingsConfirmation(
            title: "Delete Prompt Template",
            message: "Delete \"\(template.name)\"? This action cannot be undone.",
            confirmTitle: "Delete",
            itemID: templateID,
            action: { id in
                guard let id else { return }
                deleteTemplate(id: id)
            }
        )
    }

    private func exportSelectedTemplates() {
        let selectedTemplates = promptTemplates.filter { selectedTemplateIDs.contains($0.id) }
        guard !selectedTemplates.isEmpty else { return }

        exportDocument = PromptExportDocument(
            templates: selectedTemplates.map { PromptTemplateExportData($0) }
        )
        isExporting = true
        vxAtelierPro.log.log("Exporting \(selectedTemplates.count) prompt templates.")
    }

    private func importPrompts(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importMessage = "Failed to access file."
            showImportAlert = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let importedTemplates = try JSONDecoder().decode([PromptTemplateExportData].self, from: data)

            for templateData in importedTemplates {
                try queryManager.insert(templateData.toDataItem())
            }

            importMessage = "Successfully imported \(importedTemplates.count) prompts."
            vxAtelierPro.log.log("Successfully imported \(importedTemplates.count) prompts from \(url.path).")
        } catch {
            importMessage = "Failed to import prompts: \(error.localizedDescription)"
            vxAtelierPro.log.error("Failed to import prompts: \(error.localizedDescription)")
        }
        showImportAlert = true
    }
}
