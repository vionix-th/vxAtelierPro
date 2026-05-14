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
                        editingConfig = EditingConfig(config: config, isNew: false)
                    }
                ) { config in
                    SettingsEntityRow(
                        title: config.name,
                        subtitle: "Provider: \(config.provider)",
                        metadata: metadata(for: config),
                        systemImages: config.isDefault ? ["star.fill"] : []
                    )
                } actions: { config in
                    [
                        SettingsEntityAction(title: "Edit", systemImage: "pencil") {
                            editingConfig = EditingConfig(config: config, isNew: false)
                        },
                        SettingsEntityAction(title: "Delete", systemImage: "trash", role: .destructive) {
                            confirmation = SettingsConfirmation(
                                title: "Delete Web Search Configuration",
                                message: "Delete \"\(config.name)\"? This action cannot be undone.",
                                confirmTitle: "Delete",
                                action: { deleteWebSearchConfiguration(config) }
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

    private func deleteWebSearchConfiguration(_ config: WebSearchConfigurationItem) {
        do {
            try queryManager.delete(config)
        } catch {
            webSearchConfigErrorMessage = "Failed to delete configuration \(config.name): \(error.localizedDescription)"
            showWebSearchConfigError = true
        }
    }
}
