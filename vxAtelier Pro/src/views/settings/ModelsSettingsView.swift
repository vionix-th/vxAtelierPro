import SwiftUI
import SwiftData

struct ModelsSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    @Query(sort: [SortDescriptor(\ModelItem.name)]) private var models: [ModelItem]
    @State private var isUpdatingModels = false
    @State private var updateError: Error?
    @State private var updateModelsRequested = false
    @State private var editingModel: EditingModel?
    @State private var showCompletionAlert = false
    @State private var completionMessage: String = ""
    @State private var confirmationContext: ConfirmationContext? = nil
    @State private var showConfirmation: Bool = false

    init() {}

    struct EditingModel: Identifiable {
        let id = UUID()
        var model: ModelItem
        var isNew: Bool
    }

    struct ScopedModelsSection: Identifiable {
        let config: APIConfigurationItem
        let models: [ModelItem]

        var id: PersistentIdentifier { config.persistentModelID }
    }

    private func showCompletion(message: String) {
        completionMessage = message
        showCompletionAlert = true
    }

    private func handleConfirmation() {
        switch confirmationContext {
        case .deleteAllModels:
            deleteAllModels()
        default:
            break
        }
    }

    private func deleteAllModels() {
        do {
            let count = try queryManager.deleteAllModels()
            showCompletion(message: "Successfully deleted \(count) models")
        } catch {
            showCompletion(message: "Failed to delete all models: \(error.localizedDescription)")
        }
    }

    private var modelsByConfiguration: [ScopedModelsSection] {
        apiConfigurations.compactMap { config in
            let scopedModels = models.filter { $0.apiConfiguration?.id == config.id }
            guard !scopedModels.isEmpty else { return nil }
            return ScopedModelsSection(config: config, models: scopedModels)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action Bar at the top
            SettingsActionBar(
                primaryLabel: {
                    Label("Update Model List", systemImage: "arrow.triangle.2.circlepath")
                },
                primaryAction: {
                    Task {
                        isUpdatingModels = true
                        updateError = nil
                        defer { isUpdatingModels = false }
                        await queryManager.fetchModelsFromProviders()
                        showCompletion(message: "Model list updated successfully.")
                    }
                },
                secondaryActions: [
                    SettingsActionBar.ActionItem(
                        title: "Remove All Models",
                        iconName: "trash",
                        isDestructive: true
                    ) {
                        confirmationContext = .deleteAllModels
                        showConfirmation = true
                    }
                ],
                showAddButton: true,
                addAction: {
                    editingModel = EditingModel(
                        model: ModelItem(
                            name: "New Model",
                            contextSize: AppDefaults.ModelContextSizes.defaultSize,
                            provider: apiConfigurations.first?.providerIDEnum.displayName ?? "Custom",
                            apiConfiguration: apiConfigurations.first
                        ),
                        isNew: true
                    )
                },
                addLabel: {
                    Label("Add Model", systemImage: "plus")
                }
            )
            .padding(.vertical, AppDefaults.paddingSmall)
            .padding(.horizontal, AppDefaults.paddingSmall)

            // Main Content
            if isUpdatingModels {
                ProgressView("Updating models...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apiConfigurations.isEmpty {
                ContentUnavailableView(
                    "No API Configurations",
                    systemImage: "key",
                    description: Text("Add API configurations in the API tab to fetch available models")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if models.isEmpty {
                ContentUnavailableView(
                    "No Models Available",
                    systemImage: "cpu",
                    description: Text("Use the Update Model List button to fetch models from your API providers")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(modelsByConfiguration) { entry in
                        Section(header: Text(entry.config.name)) {
                            ForEach(entry.models) { model in
                                SettingsListRow(
                                    title: model.name,
                                    subtitle: model.apiConfiguration?.providerIDEnum.displayName ?? model.provider,
                                    icons: model.capabilities.map { Image(systemName: $0.systemName) },
                                    onEdit: {
                                        editingModel = EditingModel(model: model, isNew: false)
                                    },
                                    onDelete: {
                                        do {
                                            try queryManager.delete(model)
                                        } catch {
                                            showCompletion(message: "Failed to delete model: \(error.localizedDescription)")
                                        }
                                    }
                                ) {
                                    Text("Context size: \(model.contextSize)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .settingsRowActions(
                                    onEdit: {
                                        editingModel = EditingModel(model: model, isNew: false)
                                    },
                                    onDelete: {
                                        do {
                                            try queryManager.delete(model)
                                        } catch {
                                            showCompletion(message: "Failed to delete model: \(error.localizedDescription)")
                                        }
                                    }
                                )
                            }
                        }
                    }
                    if let error = updateError {
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(AppDefaults.paddingSmall)
                    }
                }  
            }
        }
        .navigationTitle("Models")
        .sheet(item: $editingModel) { editing in
            ModelEditorView(model: editing.model)
        }
        .alert(completionMessage, isPresented: $showCompletionAlert) {
            Button("OK", role: .cancel) { }
        }
        .alert(
            confirmationContext?.title ?? "",
            isPresented: $showConfirmation,
            presenting: confirmationContext
        ) { context in
            Button(context.confirmButtonTitle, role: .destructive) {
                handleConfirmation()
            }
            Button("Cancel", role: .cancel) { }
        } message: { context in
            Text(context.message)
        }
    }
} 
