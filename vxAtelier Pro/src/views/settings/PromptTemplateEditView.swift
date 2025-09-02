import SwiftUI
import SwiftData


// MARK: - Prompt Template Edit View

/// A view for editing or creating a prompt template.
/// Provides controls for setting name, category, summary, and prompt content.
///
/// Requirements:
/// - Must be presented within a NavigationStack
///
/// Constraints:
/// - Template names must be unique
/// - All fields are required except summary
struct PromptTemplateEditView: View {
    // MARK: - Environment & Properties
    
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: PromptTemplate
    let isNewTemplate: Bool
    let templates: [PromptTemplate]
    var onComplete: (Bool) -> Void
    
    // MARK: - State
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    // MARK: - View Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppDefaults.paddingLarge) {
                // Basic Settings Section
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Basic Settings")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, AppDefaults.paddingSmall)
                        .padding(.horizontal, AppDefaults.paddingSmall)
                    
                    VStack(spacing: AppDefaults.paddingMedium) {
                        // Name Field
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Template Name", text: $template.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // Category Picker
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Category")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Picker("", selection: $template.category) {
                                Label("User", systemImage: "person")
                                    .tag(PromptTemplate.Category.User)
                                Label("System", systemImage: "gear")
                                    .tag(PromptTemplate.Category.System)
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Summary Field
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Summary (Optional)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Brief description of the template", text: $template.summary)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(AppDefaults.paddingLarge)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
                    .padding(.horizontal, AppDefaults.paddingLarge)
                }
                
                // Prompt Content Section
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Prompt Content")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppDefaults.paddingLarge)
                    
                    TextEditor(text: $template.prompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .cornerRadius(AppDefaults.cornerRadiusMedium)
                        .padding(AppDefaults.paddingSmall)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
                        .padding(.horizontal, AppDefaults.paddingLarge)
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge)
        }
        .navigationTitle(isNewTemplate ? "New Template" : "Edit Template")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    vxAtelierPro.log.debug("📝 PromptTemplateEditView: Edit cancelled")
                    onComplete(false)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    // Validate input
                    if template.name.isEmpty {
                        errorMessage = "Template name cannot be empty."
                        showError = true
                        return
                    }
                    
                    if template.prompt.isEmpty {
                        errorMessage = "Prompt content cannot be empty."
                        showError = true
                        return
                    }
                    
                    // Check for name uniqueness
                    let existingTemplate = templates.first { item in
                        item.name.lowercased() == template.name.lowercased() &&
                        item.persistentModelID != template.persistentModelID
                    }
                    
                    if let _ = existingTemplate {
                        vxAtelierPro.log.warning("📝 PromptTemplateEditView: Duplicate template name attempted: '\(template.name)'")
                        errorMessage = "A template with this name already exists."
                        showError = true
                        return
                    }
                    
                    vxAtelierPro.log.notice("📝 PromptTemplateEditView: Template saved: '\(template.name)'")
                    onComplete(true)
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
