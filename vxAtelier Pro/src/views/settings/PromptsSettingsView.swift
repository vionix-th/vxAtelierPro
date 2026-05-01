import SwiftUI
import SwiftData

struct PromptsSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\PromptTemplate.name)]) private var promptTemplates: [PromptTemplate]
    @State private var editingTemplate: EditingTemplate?
    @State private var showPromptTemplateError = false
    @State private var promptTemplateErrorMessage = ""

    // Selection mode state
    @State private var selectionMode = false
    @State private var selectedTemplateIDs: Set<PersistentIdentifier> = []
    @State private var isExporting = false
    @State private var exportDocument: PromptExportDocument?
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    // Define a concrete type for the action bar to resolve generic inference issues
    typealias CurrentSettingsActionBar = SettingsActionBar<Label<Text, Image>, EmptyView>

    struct EditingTemplate: Identifiable {
        let id = UUID()
        var template: PromptTemplate
        var isNew: Bool
    }

    private func addTemplate() {
        editingTemplate = EditingTemplate(template: PromptTemplate(name: "New Template", summary: "", prompt: "", category: .User), isNew: true)
    }

    private func exportSelectedTemplates() {
        let selectedTemplates = promptTemplates.filter { selectedTemplateIDs.contains($0.id) }
        guard !selectedTemplates.isEmpty else { return }

        let exportData = selectedTemplates.map { PromptTemplateExportData($0) }
        exportDocument = PromptExportDocument(templates: exportData)
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
            let decoder = JSONDecoder()
            let importedTemplates = try decoder.decode([PromptTemplateExportData].self, from: data)

            for templateData in importedTemplates {
                let newTemplate = templateData.toDataItem()
                try queryManager.insert(newTemplate)
            }

            importMessage = "Successfully imported \(importedTemplates.count) prompts."
            vxAtelierPro.log.log("Successfully imported \(importedTemplates.count) prompts from \(url.path).")
        } catch {
            importMessage = "Failed to import prompts: \(error.localizedDescription)"
            vxAtelierPro.log.error("Failed to import prompts: \(error.localizedDescription)")
        }
        showImportAlert = true
    }

    private var actionBarSecondaryActions: [CurrentSettingsActionBar.ActionItem] {
        var actions: [CurrentSettingsActionBar.ActionItem] = []

        if selectionMode {
            if selectedTemplateIDs.isEmpty {
                // Show Cancel button when no items are selected
                actions.append(CurrentSettingsActionBar.ActionItem(
                    title: "Cancel Export",
                    iconName: "xmark.circle",
                    handler: {
                        selectionMode = false
                        selectedTemplateIDs.removeAll()
                    }
                ))
            } else {
                // Show Export button when items are selected
                actions.append(CurrentSettingsActionBar.ActionItem(
                    title: "Export Selected",
                    iconName: "square.and.arrow.up",
                    handler: exportSelectedTemplates
                ))
            }

            // Always show Select All/None in selection mode
            let allSelected = selectedTemplateIDs.count == promptTemplates.count
            actions.append(CurrentSettingsActionBar.ActionItem(
                title: allSelected ? "Select None" : "Select All",
                iconName: allSelected ? "circle" : "checkmark.circle.fill",
                handler: {
                    if allSelected {
                        selectedTemplateIDs.removeAll()
                    } else {
                        selectedTemplateIDs = Set(promptTemplates.map { $0.id })
                    }
                }
            ))
        } else {
            // Show Import and Export buttons
            actions.append(CurrentSettingsActionBar.ActionItem(
                title: "Import",
                iconName: "square.and.arrow.down",
                handler: { showImporter = true }
            ))
            actions.append(CurrentSettingsActionBar.ActionItem(
                title: "Export",
                iconName: "square.and.arrow.up",
                handler: { selectionMode = true }
            ))
        }

        return actions
    }

    var body: some View {
        VStack(spacing: 0) {
            CurrentSettingsActionBar(
                primaryLabel: {
                    Label("Add Template", systemImage: "plus.circle.fill")
                },
                primaryAction: {
                    addTemplate()
                },
                secondaryActions: actionBarSecondaryActions,
                showAddButton: false,
                addLabel: { EmptyView() }
            )
            .font(.headline)
            .padding(.vertical, AppDefaults.paddingSmall)
            .padding(.horizontal, AppDefaults.paddingSmall)

            PromptTemplateList(
                selectionMode: selectionMode,
                selectedIDs: selectedTemplateIDs,
                onSelect: { id in
                    selectedTemplateIDs.insert(id)
                    vxAtelierPro.log.log("Selected template id: \(id)")
                },
                onDeselect: { id in
                    selectedTemplateIDs.remove(id)
                    vxAtelierPro.log.log("Deselected template id: \(id)")
                },
                onTemplateActivated: { template in
                    editingTemplate = EditingTemplate(template: template, isNew: false)
                },
                onAddTemplate: {
                    addTemplate()
                }
            )
            .padding(.horizontal, AppDefaults.paddingSmall)
        }
        .navigationTitle("Prompts")
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
            // Exit selection mode after export is complete or cancelled
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
        .alert("Import Complete", isPresented: $showImportAlert, presenting: importMessage) { message in
            Button("OK") { }
        } message: { message in
            Text(message)
        }
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
                                } else {
                                    try queryManager.saveContext()
                                }
                            } catch {
                                promptTemplateErrorMessage = "Failed to save template: \(error.localizedDescription)"
                                showPromptTemplateError = true
                            }
                        }
                        editingTemplate = nil
                    }
                )
            }
        }
        .alert("Template Error", isPresented: $showPromptTemplateError) {
            Button("OK") { showPromptTemplateError = false }
        } message: {
            Text(promptTemplateErrorMessage)
        }
    }
} 
