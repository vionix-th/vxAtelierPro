import SwiftUI
import SwiftData

/// Transient payload used when saving prompt templates.
struct PromptTemplateDraft {
    let name: String
    let category: PromptTemplate.Category
    let summary: String
    let prompt: String
}

/// Snapshot used for duplicate-name validation without retaining live models.
struct PromptTemplateIdentity: Identifiable {
    let id: PersistentIdentifier
    let name: String
}

/// Editor for prompt template records.
struct PromptTemplateEditView: View {
    @Environment(\.dismiss) private var dismiss
    let templateID: PersistentIdentifier?
    let isNewTemplate: Bool
    let existingTemplates: [PromptTemplateIdentity]
    var onCancel: () -> Void
    var onSave: (PersistentIdentifier?, PromptTemplateDraft) -> String?

    @State private var name: String
    @State private var category: PromptTemplate.Category
    @State private var summary: String
    @State private var prompt: String
    @State private var showError = false
    @State private var errorMessage = ""

    init(
        templateID: PersistentIdentifier?,
        draft: PromptTemplateDraft,
        isNewTemplate: Bool,
        existingTemplates: [PromptTemplateIdentity],
        onCancel: @escaping () -> Void,
        onSave: @escaping (PersistentIdentifier?, PromptTemplateDraft) -> String?
    ) {
        self.templateID = templateID
        self.isNewTemplate = isNewTemplate
        self.existingTemplates = existingTemplates
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _category = State(initialValue: draft.category)
        _summary = State(initialValue: draft.summary)
        _prompt = State(initialValue: draft.prompt)
    }

    var body: some View {
        SettingsPage(title: isNewTemplate ? "New Template" : "Edit Template") {
            SettingsFormSection("Basic Settings") {
                LabeledContent("Name") {
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsPickerRow("Category", selection: $category) {
                    Label("User", systemImage: "person")
                        .tag(PromptTemplate.Category.User)
                    Label("System", systemImage: "gear")
                        .tag(PromptTemplate.Category.System)
                }
                LabeledContent("Summary") {
                    TextField("", text: $summary)
                        .textFieldStyle(.roundedBorder)
                }
            }

            SettingsFormSection("Prompt Content") {
                TextEditor(text: $prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 240)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    vxAtelierPro.log.debug("Prompt template edit cancelled")
                    onCancel()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        errorMessage = "Template name cannot be empty."
                        showError = true
                        return
                    }
                    
                    if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        errorMessage = "Prompt content cannot be empty."
                        showError = true
                        return
                    }
                    
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let existingTemplate = existingTemplates.first { item in
                        item.name.lowercased() == trimmedName.lowercased() &&
                        item.id != templateID
                    }
                    
                    if existingTemplate != nil {
                        vxAtelierPro.log.warning("Duplicate template name attempted: '\(trimmedName)'")
                        errorMessage = "A template with this name already exists."
                        showError = true
                        return
                    }
                    
                    let draft = PromptTemplateDraft(
                        name: trimmedName,
                        category: category,
                        summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                        prompt: prompt
                    )
                    if let saveError = onSave(templateID, draft) {
                        errorMessage = saveError
                        showError = true
                    } else {
                        vxAtelierPro.log.notice("Prompt template saved: '\(trimmedName)'")
                        onCancel()
                    }
                }
            }
        }
        .alert("Template Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }
}
