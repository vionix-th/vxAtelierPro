import SwiftUI
import SwiftData

/// View for editing or creating a Web Search configuration.
struct WebSearchConfigurationEditView: View {
    // MARK: - Environment & Properties
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\WebSearchConfigurationItem.name)]) private var webSearchConfigurations: [WebSearchConfigurationItem]

    @Bindable var configuration: WebSearchConfigurationItem
    var isNewConfiguration: Bool

    // MARK: - State

    // Local state to avoid constant model updates
    @State private var name: String
    @State private var provider: WebSearchProvider // Use the enum
    @State private var apiKey: String
    @State private var searchEngineId: String
    @State private var isDefault: Bool

    // UI state
    @State private var isAPIKeyVisible = false
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""

    // MARK: - Initialization

    init(configuration: WebSearchConfigurationItem, isNewConfiguration: Bool = false) {
        self.configuration = configuration
        self.isNewConfiguration = isNewConfiguration

        // Initialize state from the configuration
        _name = State(initialValue: configuration.name)
        // Safely initialize provider enum from stored string
        _provider = State(initialValue: WebSearchProvider(rawValue: configuration.provider) ?? .google) // Default to Google if invalid
        _apiKey = State(initialValue: configuration.apiKey ?? "")
        _searchEngineId = State(initialValue: configuration.searchEngineId ?? "")
        _isDefault = State(initialValue: configuration.isDefault)
    }

    // MARK: - View Body

    var body: some View {
        ScrollView {
            // Main VStack with consistent spacing and padding
            VStack(spacing: AppDefaults.paddingLarge) { 
                // Basic Information Section
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Basic Information")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppDefaults.paddingLarge) // Padding for the section header
                    
                    VStack(spacing: AppDefaults.paddingMedium) {
                        // Name Field
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Configuration Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("My Search Config", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal, AppDefaults.paddingSmall) // Inner padding for content

                        // Provider Picker
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Provider")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Picker("Provider", selection: $provider) {
                                ForEach(WebSearchProvider.allCases) { p in
                                    Text(p.displayName).tag(p)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, AppDefaults.paddingSmall) // Inner padding for content

                        // Default Toggle
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Toggle(isOn: $isDefault) {
                                HStack(spacing: 6) { // Consistent spacing
                                    Image(systemName: isDefault ? "star.fill" : "star")
                                        .foregroundColor(isDefault ? .yellow : .secondary)
                                    Text("Use as Default Configuration")
                                        .foregroundColor(.primary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                        .padding(.horizontal, AppDefaults.paddingSmall) // Inner padding for content
                    }
                    .padding(AppDefaults.paddingLarge) // Padding around the content block
                    .background(Color.secondary.opacity(AppDefaults.sectionBackgroundOpacity)) // Background style
                    .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium)) // Rounded corners
                    .padding(.horizontal, AppDefaults.paddingLarge) // Padding for the whole section block
                }

                // Credentials Section (Conditional based on provider)
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Credentials & Identifiers")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppDefaults.paddingLarge) // Padding for the section header
                        
                    VStack(spacing: AppDefaults.paddingMedium) {
                        // API Key (Common for many)
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
                                if isAPIKeyVisible {
                                    TextField("Enter API Key", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                } else {
                                    SecureField("Enter API Key", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }

                                Button {
                                    isAPIKeyVisible.toggle()
                                } label: {
                                    Image(systemName: isAPIKeyVisible ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            if !apiKey.isEmpty {
                                KeyInfoView(apiKey: apiKey)
                            }
                        }
                         .padding(.horizontal, AppDefaults.paddingSmall) // Inner padding for content

                        // Search Engine ID (Specific to Google)
                        if provider == .google {
                            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                                Text("Search Engine ID (cx)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("Enter Google Search Engine ID", text: $searchEngineId)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.horizontal, AppDefaults.paddingSmall) // Inner padding for content
                        }

                        // Add fields for other providers if needed
                    }
                    .padding(AppDefaults.paddingLarge) // Padding around the content block
                    .background(Color.secondary.opacity(AppDefaults.sectionBackgroundOpacity)) // Background style
                    .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium)) // Rounded corners
                    .padding(.horizontal, AppDefaults.paddingLarge) // Padding for the whole section block
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge) // Vertical padding for the main VStack
        }
        .navigationTitle(isNewConfiguration ? "New Web Search Config" : "Edit Web Search Config")
        .alert("Validation Error", isPresented: $showValidationError) {
            Button("OK") { showValidationError = false }
        } message: {
            Text(validationErrorMessage)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if validateInputs() {
                        saveConfiguration()
                    }
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    vxAtelierPro.log.debug("🕸️ WebSearchConfigurationEditView: Edit cancelled")
                    dismiss()
                }
            }
        }
        .onChange(of: provider) { _, newProvider in
            // Clear fields not relevant to the new provider
            if newProvider != .google {
                searchEngineId = ""
            }
            // Add clearing logic for other provider-specific fields here
        }
    }

    // MARK: - Helper Views

    /// View to display API key length and copy button.
    private struct KeyInfoView: View {
        let apiKey: String

        var body: some View {
            HStack {
                Text("Key length: \(apiKey.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    copyToClipboard(apiKey)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Helper Methods

    /// Validates input fields before saving.
    private func validateInputs() -> Bool {
        // Check for empty name
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationErrorMessage = "Configuration name cannot be empty."
            showValidationError = true
            return false
        }

        // Check provider-specific requirements
        switch provider {
        case .google:
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationErrorMessage = "API Key is required for Google Custom Search."
                showValidationError = true
                return false
            }
            if searchEngineId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationErrorMessage = "Search Engine ID (cx) is required for Google Custom Search."
                showValidationError = true
                return false
            }
        case .custom:
            // Add validation for custom providers if needed
            break
        // Add cases for other providers
        }

        // Check for duplicate name (only if creating new or changing name)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNewConfiguration || trimmedName != configuration.name {
             let existingNames = webSearchConfigurations.map { $0.name }
             if existingNames.contains(where: { $0.lowercased() == trimmedName.lowercased() }) {
                 validationErrorMessage = "A web search configuration with this name already exists."
                 showValidationError = true
                 return false
             }
         }

        return true
    }

    /// Saves the configuration changes to SwiftData.
    private func saveConfiguration() {
        // Use the @Bindable configuration directly for updates
        let configToSave = configuration
        let shouldInsert = isNewConfiguration
        var needsSave = false // Track if context save is needed

        // Update properties
        if configToSave.name != name { configToSave.name = name; needsSave = true }
        let providerRawValue = provider.rawValue
        if configToSave.provider != providerRawValue { configToSave.provider = providerRawValue; needsSave = true }
        let finalApiKey = apiKey.isEmpty ? nil : apiKey
        if configToSave.apiKey != finalApiKey { configToSave.apiKey = finalApiKey; needsSave = true }
        let finalCxId = searchEngineId.isEmpty ? nil : searchEngineId
        if configToSave.searchEngineId != finalCxId { configToSave.searchEngineId = finalCxId; needsSave = true }
        if configToSave.isDefault != isDefault { configToSave.isDefault = isDefault; needsSave = true }

        do {
            try queryManager.upsertWebSearchConfiguration(configToSave, makeDefault: isDefault)
            if shouldInsert {
                vxAtelierPro.log.info("🕸️ WebSearchConfigurationEditView: Inserted config: \(configToSave.name)")
            } else if needsSave {
                vxAtelierPro.log.info("🕸️ WebSearchConfigurationEditView: Saved config: \(configToSave.name)")
            } else {
                 vxAtelierPro.log.info("🕸️ WebSearchConfigurationEditView: No changes detected for config: \(configToSave.name)")
            }
            dismiss()
        } catch {
            validationErrorMessage = "Failed to save configuration: \(error.localizedDescription)"
            showValidationError = true
            vxAtelierPro.log.error("🔴 WebSearchConfigurationEditView: Failed to save config \(configToSave.name): \(error.localizedDescription)")
        }
    }
}

/// Cross-platform clipboard copy function (should be moved to a utility file).
private func copyToClipboard(_ string: String) {
    #if os(iOS)
    UIPasteboard.general.string = string
    #elseif os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #endif
    vxAtelierPro.log.debug("📋 Copied to clipboard")
} 
