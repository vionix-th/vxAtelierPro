import SwiftData
import SwiftUI

/// Web search configuration list and editor launcher.
struct WebSearchSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\WebSearchConfigurationItem.name)]) private var webSearchConfigurations: [WebSearchConfigurationItem]
    @State private var editingConfig: EditingConfig?
    @State private var showWebSearchConfigError = false
    @State private var webSearchConfigErrorMessage = ""
    @State private var confirmation: SettingsConfirmation?

    /// In-memory state for a web search configuration being edited.
    struct EditingConfig: Identifiable {
        let id = UUID()
        var config: WebSearchConfigurationItem
        var isNew: Bool
    }

    var body: some View {
        SettingsListPage(title: "Web Search") {
            VStack(spacing: AppDefaults.paddingLarge) {
                SettingsPageActionRegion {
                    addWebSearchConfigButton
                }

                SettingsEntityList(
                    items: webSearchConfigurations.sorted { $0.name < $1.name },
                    emptyTitle: "No Web Search Configurations",
                    emptySystemImage: "magnifyingglass",
                    emptyDescription: "Add a web search configuration to enable the search tool.",
                    selectionAction: { config in
                        editConfiguration(id: config.id)
                    }
                ) { config in
                    SettingsEntityRow(
                        title: config.name,
                        subtitle: "Provider: \(config.provider)",
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
                                title: "Delete Web Search Configuration",
                                message: "Delete \"\(configName)\"? This action cannot be undone.",
                                confirmTitle: "Delete",
                                itemID: configID,
                                action: { id in
                                    guard let id else { return }
                                    deleteWebSearchConfiguration(id: id)
                                }
                            )
                        }
                    ]
                }
            }
        }
        .settingsNavigationActions {
            addWebSearchConfigButton
        }
        .alert("Web Search Config Error", isPresented: $showWebSearchConfigError) {
            Button("OK") { showWebSearchConfigError = false }
        } message: {
            Text(webSearchConfigErrorMessage)
        }
        .sheet(item: $editingConfig) { editing in
            NavigationStack {
                WebSearchConfigurationEditView(
                    configuration: editing.config,
                    isNewConfiguration: editing.isNew
                )
            }
        }
        .settingsConfirmationDialog($confirmation)
    }

    private var addWebSearchConfigButton: some View {
        Button {
            editingConfig = EditingConfig(
                config: WebSearchConfigurationItem(
                    name: "New Web Search Config",
                    provider: WebSearchProvider.google.rawValue
                ),
                isNew: true
            )
        } label: {
            Label("Add Web Search Config", systemImage: "plus")
        }
    }

    private func metadata(for config: WebSearchConfigurationItem) -> String? {
        var values: [String] = []
        if let key = config.apiKey, !key.isEmpty {
            values.append("API Key: \(key.prefix(4))...\(key.suffix(4))")
        }
        if let cx = config.searchEngineId, !cx.isEmpty {
            values.append("Engine ID: \(cx)")
        }
        return values.isEmpty ? nil : values.joined(separator: "  ")
    }

    private func editConfiguration(id: PersistentIdentifier) {
        guard let config = webSearchConfigurations.first(where: { $0.id == id }) else { return }
        editingConfig = EditingConfig(config: config, isNew: false)
    }

    private func deleteWebSearchConfiguration(id: PersistentIdentifier) {
        do {
            guard let config = webSearchConfigurations.first(where: { $0.id == id }) else { return }
            try queryManager.delete(config)
        } catch {
            let configName = webSearchConfigurations.first(where: { $0.id == id })?.name ?? "configuration"
            webSearchConfigErrorMessage = "Failed to delete configuration \(configName): \(error.localizedDescription)"
            showWebSearchConfigError = true
        }
    }
}
