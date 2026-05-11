import SwiftUI
import SwiftData

struct ModelsSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    @Query(sort: [SortDescriptor(\ModelItem.modelID)]) private var models: [ModelItem]
    @State private var isUpdatingModels = false
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

    private func presentCompletionAlert(_ message: String) {
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
            presentCompletionAlert("Successfully deleted \(count) models")
        } catch {
            presentCompletionAlert("Failed to delete all models: \(error.localizedDescription)")
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
                                            defer { isUpdatingModels = false }
                                            let summary = await queryManager.fetchModelsFromProviders()
                                            if summary.failures.isEmpty {
                                                presentCompletionAlert("Model list updated: \(summary.updated) updated, \(summary.added) added.")
                                            } else {
                                                let failures = summary.failures
                                                    .map { "\($0.configurationName): \($0.message)" }
                                                    .joined(separator: "\n")
                                                presentCompletionAlert(
                                                    "Model list update failed for \(summary.failures.count) provider(s).\n\(failures)"
                                                )
                                            }
                                        }
                                    },
                                    secondaryActions: [
                                        SettingsActionBar.MenuAction(
                                            title: "Remove All Models",
                                            iconName: "trash",
                                            isDestructive: true
                                        ) {
                                            confirmationContext = .deleteAllModels
                                            showConfirmation = true
                                        }
                                    ],
                                    addAction: {
                                        editingModel = EditingModel(
                                            model: ModelItem(
                                                modelID: "New Model",
                                                contextSize: AppDefaults.ModelContextSizes.defaultSize,
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
                                    subtitle: model.apiConfiguration?.providerIDEnum.displayName ?? "No API Configuration",
                                    onEdit: {
                                        editingModel = EditingModel(model: model, isNew: false)
                                    },
                                    onDelete: {
                                        do {
                                            try queryManager.delete(model)
                                        } catch {
                                            presentCompletionAlert("Failed to delete model: \(error.localizedDescription)")
                                        }
                                    }
                                ) {
                                    Text("Context size: \(model.contextSize)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
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
