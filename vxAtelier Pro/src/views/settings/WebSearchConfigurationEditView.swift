import SwiftData
import SwiftUI

/// Rollback snapshot for web search configuration edits.
private struct WebSearchConfigurationSnapshot {
    let name: String
    let provider: String
    let apiKey: String?
    let searchEngineID: String?
    let isDefault: Bool

    init(_ configuration: WebSearchConfigurationItem) {
        name = configuration.name
        provider = configuration.provider
        apiKey = configuration.apiKey
        searchEngineID = configuration.searchEngineId
        isDefault = configuration.isDefault
    }

    func restore(_ configuration: WebSearchConfigurationItem) {
        configuration.name = name
        configuration.provider = provider
        configuration.apiKey = apiKey
        configuration.searchEngineId = searchEngineID
        configuration.isDefault = isDefault
    }
}

/// Editor for web search configuration records.
struct WebSearchConfigurationEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\WebSearchConfigurationItem.name)]) private var webSearchConfigurations: [WebSearchConfigurationItem]

    let configuration: WebSearchConfigurationItem
    var isNewConfiguration: Bool

    @State private var name: String
    @State private var provider: WebSearchProvider
    @State private var apiKey: String
    @State private var searchEngineId: String
    @State private var isDefault: Bool
    @State private var isAPIKeyVisible = false
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""

    init(configuration: WebSearchConfigurationItem, isNewConfiguration: Bool = false) {
        self.configuration = configuration
        self.isNewConfiguration = isNewConfiguration
        _name = State(initialValue: configuration.name)
        _provider = State(initialValue: WebSearchProvider(rawValue: configuration.provider) ?? .google)
        _apiKey = State(initialValue: configuration.apiKey ?? "")
        _searchEngineId = State(initialValue: configuration.searchEngineId ?? "")
        _isDefault = State(initialValue: configuration.isDefault)
    }

    var body: some View {
        SettingsPage(title: isNewConfiguration ? "New Web Search Config" : "Edit Web Search Config") {
            SettingsFormSection("Basic Information") {
                LabeledContent("Configuration Name") {
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsPickerRow("Provider", selection: $provider) {
                    ForEach(WebSearchProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                SettingsToggleRow("Use as Default Configuration", isOn: $isDefault)
            }

            SettingsFormSection("Credentials & Identifiers") {
                LabeledContent("API Key") {
                    HStack {
                        Group {
                            if isAPIKeyVisible {
                                TextField("", text: $apiKey)
                            } else {
                                SecureField("", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button {
                            isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: isAPIKeyVisible ? "eye.slash.fill" : "eye.fill")
                        }
                        .buttonStyle(.borderless)
                        .help(isAPIKeyVisible ? "Hide API key" : "Show API key")

                        if !apiKey.isEmpty {
                            Button {
                                ExportUtils.copyToClipboard(apiKey)
                                vxAtelierPro.log.debug("Copied web search API key to clipboard")
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy API key")
                        }
                    }
                }

                if provider == .google {
                    LabeledContent("Search Engine ID (cx)") {
                        TextField("", text: $searchEngineId)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
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
                    dismiss()
                }
            }
        }
        .alert("Validation Error", isPresented: $showValidationError) {
            Button("OK") { showValidationError = false }
        } message: {
            Text(validationErrorMessage)
        }
        .onChange(of: provider) { _, newProvider in
            if newProvider != .google {
                searchEngineId = ""
            }
        }
    }

    private func validateInputs() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            validationErrorMessage = "Configuration name cannot be empty."
            showValidationError = true
            return false
        }

        if provider == .google {
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
        }

        if isNewConfiguration || trimmedName != configuration.name {
            let existingConfiguration = webSearchConfigurations.first { item in
                item.name.lowercased() == trimmedName.lowercased() &&
                item.persistentModelID != configuration.persistentModelID
            }
            if existingConfiguration != nil {
                validationErrorMessage = "A web search configuration with this name already exists."
                showValidationError = true
                return false
            }
        }

        return true
    }

    private func saveConfiguration() {
        let snapshot = WebSearchConfigurationSnapshot(configuration)

        configuration.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.provider = provider.rawValue
        configuration.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.searchEngineId = searchEngineId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : searchEngineId.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.isDefault = isDefault

        do {
            try queryManager.upsertWebSearchConfiguration(configuration, makeDefault: isDefault)
            dismiss()
        } catch {
            snapshot.restore(configuration)
            validationErrorMessage = "Failed to save configuration: \(error.localizedDescription)"
            showValidationError = true
        }
    }
}
