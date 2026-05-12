import SwiftUI
import SwiftData

struct ModelsSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    @Query(sort: [SortDescriptor(\ModelItem.modelID)]) private var models: [ModelItem]
    @State private var isUpdatingModels = false
    @State private var searchText = ""
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

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isFiltering: Bool {
        !normalizedSearchText.isEmpty
    }

    private func modelMatchesSearch(_ model: ModelItem) -> Bool {
        guard isFiltering else { return true }

        let searchCorpus = [
            model.modelID,
            model.displayName,
            model.apiConfiguration?.name ?? "",
            model.apiConfiguration?.providerIDEnum.displayName ?? "",
            String(model.contextSize),
            model.capabilities.map(\.rawValue).joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return searchCorpus.contains(normalizedSearchText)
    }

    private var filteredModelsByConfiguration: [ScopedModelsSection] {
        apiConfigurations.compactMap { config in
            let scopedModels = models.filter {
                $0.apiConfiguration?.id == config.id && modelMatchesSearch($0)
            }
            guard !scopedModels.isEmpty else { return nil }
            return ScopedModelsSection(config: config, models: scopedModels)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppDefaults.paddingMedium) {
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

                HStack(spacing: AppDefaults.paddingMedium) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Filter models", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(AppDefaults.paddingLarge)

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
            } else if filteredModelsByConfiguration.isEmpty {
                ContentUnavailableView(
                    "No Matching Models",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("No models match \"\(searchText)\"")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredModelsByConfiguration) { entry in
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
