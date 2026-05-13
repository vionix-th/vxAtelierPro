import SwiftData
import SwiftUI

struct APISettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    @State private var editingConfig: EditingConfig?
    @State private var showApiConfigError = false
    @State private var apiConfigErrorMessage = ""
    @State private var showSaveWarning = false
    @State private var saveWarningMessage = ""
    @State private var didPresentInitialEditor = false
    @State private var confirmation: SettingsConfirmation?

    struct EditingConfig: Identifiable {
        let id = UUID()
        var config: APIConfigurationItem
        var isNew: Bool
    }

    var body: some View {
        SettingsListPage(title: "API") {
            SettingsEntityList(
                items: apiConfigurations.sorted { $0.name < $1.name },
                emptyTitle: "No API Configurations",
                emptySystemImage: "key",
                emptyDescription: "Add an API configuration to enable chatting and model fetching.",
                selectionAction: { config in
                    editingConfig = EditingConfig(config: config, isNew: false)
                }
            ) { config in
                SettingsEntityRow(
                    title: config.name,
                    subtitle: config.baseURL,
                    metadata: config.apiKey.isEmpty
                        ? nil
                        : "API Key: \(config.apiKey.prefix(4))...\(config.apiKey.suffix(4))",
                    systemImages: config.isDefault ? ["star.fill"] : []
                )
            } actions: { config in
                [
                    SettingsEntityAction(title: "Edit", systemImage: "pencil") {
                        editingConfig = EditingConfig(config: config, isNew: false)
                    },
                    SettingsEntityAction(title: "Delete", systemImage: "trash", role: .destructive) {
                        confirmation = SettingsConfirmation(
                            title: "Delete API Configuration",
                            message: "Delete \"\(config.name)\"? Models using this configuration will be cleaned up.",
                            confirmTitle: "Delete",
                            action: { deleteAPIConfiguration(config) }
                        )
                    }
                ]
            }
        }
        .toolbar {
            ToolbarItem(placement: .settingsPrimary) {
                Button {
                    startNewConfiguration()
                } label: {
                    Label("Add Configuration", systemImage: "plus")
                }
            }
        }
        .onAppear {
            if apiConfigurations.isEmpty && !didPresentInitialEditor {
                didPresentInitialEditor = true
                startNewConfiguration()
            }
        }
        .alert("Configuration Error", isPresented: $showApiConfigError) {
            Button("OK") {
                showApiConfigError = false
            }
        } message: {
            Text(apiConfigErrorMessage)
        }
        .alert("Model Refresh Failed", isPresented: $showSaveWarning) {
            Button("OK") {
                showSaveWarning = false
            }
        } message: {
            Text(saveWarningMessage)
        }
        .sheet(item: $editingConfig) { editing in
            NavigationStack {
                APIConfigurationEditView(
                    configuration: editing.config,
                    isNewConfiguration: editing.isNew
                ) { warningMessage in
                    saveWarningMessage = warningMessage
                    showSaveWarning = true
                }
            }
        }
        .settingsConfirmationDialog($confirmation)
    }

    private func deleteAPIConfiguration(_ config: APIConfigurationItem) {
        do {
            try queryManager.cleanupReferences(for: config)
            try queryManager.delete(config)
        } catch {
            apiConfigErrorMessage = "Failed to delete configuration \(config.name): \(error.localizedDescription)"
            showApiConfigError = true
        }
    }

    private func startNewConfiguration() {
        editingConfig = EditingConfig(
            config: APIConfigurationItem(
                name: "New Configuration",
                apiKey: "",
                baseURL: AppDefaults.OpenAi.baseURL,
                isDefault: apiConfigurations.count < 2
            ),
            isNew: true
        )
    }
}
