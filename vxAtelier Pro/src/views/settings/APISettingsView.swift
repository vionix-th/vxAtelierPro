import SwiftUI

struct APISettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @State private var editingConfig: EditingConfig?
    @State private var showApiConfigError = false
    @State private var apiConfigErrorMessage = ""
    @State private var didPresentInitialEditor = false

    struct EditingConfig: Identifiable {
        let id = UUID()
        var config: APIConfigurationItem
        var isNew: Bool
    }

    private func isDefaultConfiguration(_ config: APIConfigurationItem) -> Bool {
        return config.isDefault
    }

    private func deleteAPIConfiguration(_ config: APIConfigurationItem) {
        let configWasDefault = config.isDefault
        do {
            try queryManager.cleanupReferences(for: config)
            try queryManager.delete(config)
            if configWasDefault {
                if let newDefault = queryManager.apiConfigurations.sorted(by: { $0.name < $1.name }).first {
                    newDefault.isDefault = true
                    try queryManager.saveContext()
                }
            }
        } catch {
            apiConfigErrorMessage = "Failed to delete configuration \(config.name): \(error.localizedDescription)"
            showApiConfigError = true
        }
    }

    private func startNewConfiguration() {
        editingConfig = EditingConfig(config: APIConfigurationItem(
            name: "New Configuration",
            apiKey: "",
            baseURL: AppDefaults.OpenAi.baseURL,
            chatCompletionsEndpoint: AppDefaults.OpenAi.chatCompletionsEndpoint,
            modelsEndpoint: AppDefaults.OpenAi.modelsEndpoint,
            isDefault: queryManager.apiConfigurations.count < 2
        ), isNew: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsActionBar(
                primaryLabel: {
                    Label("Add Configuration", systemImage: "plus.circle.fill")
                        .font(.headline)
                },
                primaryAction: {
                    startNewConfiguration()
                },
                secondaryActions: [],
                showAddButton: false,
                addLabel: { EmptyView() }
            )
            .padding(.vertical, AppDefaults.paddingSmall)
            .padding(.horizontal, AppDefaults.paddingSmall)
            
            if queryManager.apiConfigurations.isEmpty {
                ContentUnavailableView(
                    "No API Configurations",
                    systemImage: "key",
                    description: Text("Add an API configuration to enable chatting and model fetching.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(queryManager.apiConfigurations.sorted { $0.name < $1.name }) { config in
                        SettingsListRow(
                            title: config.name,
                            subtitle: config.baseURL,
                            icons: isDefaultConfiguration(config) ? [Image(systemName: "star.fill")] : [],
                            onEdit: {
                                editingConfig = EditingConfig(config: config, isNew: false)
                            },
                            onDelete: {
                                deleteAPIConfiguration(config)
                            }
                        ) {
                            if !config.apiKey.isEmpty {
                                Text("API Key: \(config.apiKey.prefix(4))...\(config.apiKey.suffix(4))")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                        .settingsRowActions(
                            onEdit: {
                                editingConfig = EditingConfig(config: config, isNew: false)
                            },
                            onDelete: {
                                deleteAPIConfiguration(config)
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("API")
        .onAppear {
            if queryManager.apiConfigurations.isEmpty && !didPresentInitialEditor {
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
        .sheet(item: $editingConfig) { editing in
            NavigationStack {
                APIConfigurationEditView(
                    configuration: editing.config,
                    isNewConfiguration: editing.isNew
                )
            }
        }
    }
} 
