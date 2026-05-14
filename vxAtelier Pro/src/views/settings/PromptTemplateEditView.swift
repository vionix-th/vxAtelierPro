import SwiftUI
import SwiftData

struct PromptTemplateDraft {
    let name: String
    let category: PromptTemplate.Category
    let summary: String
    let prompt: String
}

struct PromptTemplateEditView: View {
    @Environment(\.dismiss) private var dismiss
    let template: PromptTemplate
    let isNewTemplate: Bool
    let templates: [PromptTemplate]
    var onCancel: () -> Void
    var onSave: (PromptTemplateDraft) -> String?

    @State private var name: String
    @State private var category: PromptTemplate.Category
    @State private var summary: String
    @State private var prompt: String
    @State private var showError = false
    @State private var errorMessage = ""

    init(
        template: PromptTemplate,
        isNewTemplate: Bool,
        templates: [PromptTemplate],
        onCancel: @escaping () -> Void,
        onSave: @escaping (PromptTemplateDraft) -> String?
    ) {
        self.template = template
        self.isNewTemplate = isNewTemplate
        self.templates = templates
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: template.name)
        _category = State(initialValue: template.category)
        _summary = State(initialValue: template.summary)
        _prompt = State(initialValue: template.prompt)
    }

    var body: some View {
        SettingsPage(title: isNewTemplate ? "New Template" : "Edit Template") {
            SettingsFormSection("Basic Settings") {
                LabeledContent("Name") {
                    TextField("Template Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                SettingsPickerRow("Category", selection: $category) {
                    Label("User", systemImage: "person")
                        .tag(PromptTemplate.Category.User)
                    Label("System", systemImage: "gear")
                        .tag(PromptTemplate.Category.System)
                }
                LabeledContent("Summary") {
                    TextField("Brief description of the template", text: $summary)
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
                    let existingTemplate = templates.first { item in
                        item.name.lowercased() == trimmedName.lowercased() &&
                        item.persistentModelID != template.persistentModelID
                    }
                    
                    if existingTemplate != nil {
                        vxAtelierPro.log.warning("Duplicate template name attempted: '\(template.name)'")
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
                    if let saveError = onSave(draft) {
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
