import SwiftData
import SwiftUI

/// API provider configuration list and editor launcher.
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

    /// In-memory state for an API configuration being edited.
    struct EditingConfig: Identifiable {
        let id = UUID()
        var config: APIConfigurationItem
        var isNew: Bool
    }

    var body: some View {
        SettingsListPage(title: "API") {
            VStack(spacing: AppDefaults.paddingLarge) {
                SettingsPageActionRegion {
                    addConfigurationButton
                }

                SettingsEntityList(
                    items: apiConfigurations.sorted { $0.name < $1.name },
                    emptyTitle: "No API Configurations",
                    emptySystemImage: "key",
                    emptyDescription: "Add an API configuration to enable chatting and model fetching.",
                    selectionAction: { config in
                        editConfiguration(id: config.id)
                    }
                ) { config in
                    SettingsEntityRow(
                        title: config.name,
                        subtitle: config.baseURL,
                        metadata: metadata(for: config),
                        systemImages: config.isDefault ? ["star.fill"] : []
                    )
                } actions: { config in
                    let configID = config.id
                    let configName = config.name
                    return [
                        SettingsEntityAction(title: "Edit", systemImage: "pencil") {
                            editConfiguration(id: configID)
                        },
                        SettingsEntityAction(title: "Delete", systemImage: "trash", role: .destructive) {
                            confirmation = SettingsConfirmation(
                                title: "Delete API Configuration",
                                message: "Delete \"\(configName)\"? Models using this configuration will be cleaned up.",
                                confirmTitle: "Delete",
                                itemID: configID,
                                action: { id in
                                    guard let id else { return }
                                    deleteAPIConfiguration(id: id)
                                }
                            )
                        }
                    ]
                }
            }
        }
        .settingsNavigationActions {
            addConfigurationButton
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

    private var addConfigurationButton: some View {
        Button {
            startNewConfiguration()
        } label: {
            Label("Add Configuration", systemImage: "plus")
        }
    }

    private func metadata(for config: APIConfigurationItem) -> String? {
        let profile = LLMProviderRegistry.shared.profile(for: config.providerIDEnum)
        if profile.transportKind == .localSystem {
            return LLMProviderRegistry.shared.localStatusText(for: config.providerIDEnum) ?? "On-device model"
        }
        if config.providerIDEnum == .openAICodexChatGPTSubscription {
            guard let tokenSet = config.codexChatGPTTokenSet else {
                return "Codex ChatGPT Subscription: not signed in"
            }
            return "Codex ChatGPT Subscription: \(tokenSet.email ?? tokenSet.accountID ?? "signed in")"
        }
        return config.apiKey.isEmpty ? nil : "API Key: \(config.apiKey.prefix(4))...\(config.apiKey.suffix(4))"
    }

    private func editConfiguration(id: PersistentIdentifier) {
        guard let configuration = apiConfigurations.first(where: { $0.id == id }) else { return }
        editingConfig = EditingConfig(config: configuration, isNew: false)
    }

    private func deleteAPIConfiguration(id: PersistentIdentifier) {
        do {
            guard let config = apiConfigurations.first(where: { $0.id == id }) else { return }
            try queryManager.cleanupReferences(for: config)
            try queryManager.delete(config)
        } catch {
            let configName = apiConfigurations.first(where: { $0.id == id })?.name ?? "configuration"
            apiConfigErrorMessage = "Failed to delete configuration \(configName): \(error.localizedDescription)"
            showApiConfigError = true
        }
    }

    private func startNewConfiguration() {
        let defaultPreset = APIPreset.preset(for: .openAIPlatform)
        editingConfig = EditingConfig(
            config: APIConfigurationItem(
                name: defaultPreset.displayName,
                apiKey: "",
                baseURL: defaultPreset.baseURL,
                isDefault: apiConfigurations.count < 2
            ),
            isNew: true
        )
    }
}
