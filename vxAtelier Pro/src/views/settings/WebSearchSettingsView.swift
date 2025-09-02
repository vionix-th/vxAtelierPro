import SwiftUI

struct WebSearchSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @State private var editingConfig: EditingConfig?
    @State private var showWebSearchConfigError = false
    @State private var webSearchConfigErrorMessage = ""

    struct EditingConfig: Identifiable {
        let id = UUID()
        var config: WebSearchConfigurationItem
        var isNew: Bool
    }

    private func deleteWebSearchConfiguration(_ config: WebSearchConfigurationItem) {
        let configWasDefault = config.isDefault
        do {
            try queryManager.delete(config)
            if configWasDefault {
                if let newDefault = queryManager.webSearchConfigurations.sorted(by: { $0.name < $1.name }).first {
                    newDefault.isDefault = true
                    try queryManager.saveContext()
                }
            }
        } catch {
            webSearchConfigErrorMessage = "Failed to delete configuration \(config.name): \(error.localizedDescription)"
            showWebSearchConfigError = true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsActionBar(
                primaryLabel: {
                    Label("Add Web Search Config", systemImage: "plus.circle.fill")
                        .font(.headline)
                },
                primaryAction: {
                    editingConfig = EditingConfig(config: WebSearchConfigurationItem(
                        name: "New Web Search Config",
                        provider: WebSearchProvider.google.rawValue
                    ), isNew: true)
                },
                secondaryActions: [],
                showAddButton: false,
                addLabel: { EmptyView() }
            )
            .padding(.vertical, AppDefaults.paddingSmall)
            .padding(.horizontal, AppDefaults.paddingSmall)

            List {
                ForEach(queryManager.webSearchConfigurations.sorted { $0.name < $1.name }) { config in
                    SettingsListRow(
                        title: config.name,
                        subtitle: "Provider: \(config.provider)",
                        icons: config.isDefault ? [Image(systemName: "star.fill")] : [],
                        onEdit: {
                            editingConfig = EditingConfig(config: config, isNew: false)
                        },
                        onDelete: {
                            deleteWebSearchConfiguration(config)
                        }
                    ) {
                        if let key = config.apiKey, !key.isEmpty {
                            Text("API Key: \(key.prefix(4))...\(key.suffix(4))")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        if let cx = config.searchEngineId, !cx.isEmpty {
                            Text("Engine ID: \(cx)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .settingsRowActions(
                        onEdit: {
                            editingConfig = EditingConfig(config: config, isNew: false)
                        },
                        onDelete: {
                            deleteWebSearchConfiguration(config)
                        }
                    )
                }
            }
        }
        .navigationTitle("Web Search")
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
    }
} 