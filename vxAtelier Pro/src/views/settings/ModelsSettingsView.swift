import SwiftData
import SwiftUI

/// Model list management and refresh controls.
struct ModelsSettingsView: View {
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    @Query(sort: [SortDescriptor(\ModelItem.modelID)]) private var models: [ModelItem]
    @State private var isUpdatingModels = false
    @State private var searchText = ""
    @State private var editingModel: EditingModel?
    @State private var showCompletionAlert = false
    @State private var completionMessage = ""
    @State private var confirmation: SettingsConfirmation?

    /// In-memory state for a model being edited.
    struct EditingModel: Identifiable {
        let id = UUID()
        var model: ModelItem
        var isNew: Bool
    }

    /// Display wrapper for a persisted model row.
    struct ModelRowItem: Identifiable {
        let id: PersistentIdentifier
        let modelID: String
        let providerName: String
        let providerDisplayName: String
        let contextSize: Int
        let capabilitySystemImages: [String]
        let searchCorpus: String
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredModels: [ModelRowItem] {
        models
            .map { model in
                ModelRowItem(
                    id: model.persistentModelID,
                    modelID: model.modelID,
                    providerName: model.apiConfiguration?.name ?? "No API Configuration",
                    providerDisplayName: model.apiConfiguration?.providerIDEnum.displayName ?? "Unknown",
                    contextSize: model.contextSize,
                    capabilitySystemImages: model.metadataIconSystemNames,
                    searchCorpus: [
                        model.modelID,
                        model.displayName,
                        model.apiConfiguration?.name ?? "",
                        model.apiConfiguration?.providerIDEnum.displayName ?? "",
                        String(model.contextSize),
                        model.capabilities.map(\.rawValue).joined(separator: " ")
                    ]
                    .joined(separator: " ")
                    .lowercased()
                )
            }
            .filter { row in
                guard !normalizedSearchText.isEmpty else { return true }
                return row.searchCorpus.contains(normalizedSearchText)
            }
            .sorted {
                if $0.providerName == $1.providerName {
                    return $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending
                }
                return $0.providerName.localizedCaseInsensitiveCompare($1.providerName) == .orderedAscending
            }
    }

    var body: some View {
        SettingsSearchListPage(
            title: "Models",
            searchContent: {
                VStack(spacing: AppDefaults.paddingMedium) {
                    SettingsPageActionRegion(padded: false) {
                        updateModelListButton
                        addModelButton
                        removeAllModelsButton
                    }
                    SettingsSearchField(prompt: "Filter models", text: $searchText)
                }
            },
            content: {
                content
            }
        )
        .settingsNavigationActions {
            updateModelListButton
            addModelButton
            removeAllModelsButton
        }
        .sheet(item: $editingModel) { editing in
            ModelEditorView(model: editing.model)
        }
        .alert(completionMessage, isPresented: $showCompletionAlert) {
            Button("OK", role: .cancel) { }
        }
        .settingsConfirmationDialog($confirmation)
    }

    private var updateModelListButton: some View {
        Button {
            updateModels()
        } label: {
            if isUpdatingModels {
                ProgressView()
            } else {
                Label("Update Model List", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(isUpdatingModels || apiConfigurations.isEmpty)
    }

    private var addModelButton: some View {
        Button {
            editingModel = EditingModel(
                model: ModelItem(
                    modelID: "New Model",
                    contextSize: AppDefaults.ModelContextSizes.defaultSize,
                    apiConfiguration: apiConfigurations.first
                ),
                isNew: true
            )
        } label: {
            Label("Add Model", systemImage: "plus")
        }
        .disabled(apiConfigurations.isEmpty)
    }

    private var removeAllModelsButton: some View {
        Button(role: .destructive) {
            confirmation = SettingsConfirmation(
                title: "Delete All Models",
                message: "Are you sure you want to delete all models? This action cannot be undone.",
                confirmTitle: "Delete",
                action: deleteAllModels
            )
        } label: {
            Label("Remove All Models", systemImage: "trash")
        }
        .disabled(models.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if isUpdatingModels {
            ProgressView("Updating models...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apiConfigurations.isEmpty {
            SettingsEmptyState(
                title: "No API Configurations",
                systemImage: "key",
                description: "Add API configurations in the API tab to fetch available models."
            )
        } else if models.isEmpty {
            SettingsEmptyState(
                title: "No Models Available",
                systemImage: "cpu",
                description: "Use Update Model List to fetch models from your API providers."
            )
        } else if filteredModels.isEmpty {
            SettingsEmptyState(
                title: "No Matching Models",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "No models match \"\(searchText)\"."
            )
        } else {
            SettingsEntityList(
                items: filteredModels,
                emptyTitle: "No Models Available",
                emptySystemImage: "cpu",
                emptyDescription: "Use Update Model List to fetch models from your API providers.",
                selectionAction: { row in
                    guard let model = queryManager.model(with: row.id) else { return }
                    editingModel = EditingModel(model: model, isNew: false)
                }
            ) { row in
                SettingsEntityRow(
                    title: row.modelID,
                    subtitle: row.providerName,
                    metadata: "Provider: \(row.providerDisplayName)  Context: \(row.contextSize)",
                    systemImages: row.capabilitySystemImages
                )
            } actions: { row in
                [
                    SettingsEntityAction(title: "Edit", systemImage: "pencil") {
                        guard let model = queryManager.model(with: row.id) else { return }
                        editingModel = EditingModel(model: model, isNew: false)
                    },
                    SettingsEntityAction(title: "Delete", systemImage: "trash", role: .destructive) {
                        confirmation = SettingsConfirmation(
                            title: "Delete Model",
                            message: "Delete \"\(row.modelID)\"? This action cannot be undone.",
                            confirmTitle: "Delete",
                            action: { deleteModel(id: row.id) }
                        )
                    }
                ]
            }
        }
    }

    private func updateModels() {
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
                presentCompletionAlert("Model list update failed for \(summary.failures.count) provider(s).\n\(failures)")
            }
        }
    }

    private func deleteModel(id: PersistentIdentifier) {
        do {
            editingModel = nil
            confirmation = nil
            guard let model = queryManager.model(with: id) else { return }
            try queryManager.delete(model)
        } catch {
            presentCompletionAlert("Failed to delete model: \(error.localizedDescription)")
        }
    }

    private func deleteAllModels() {
        do {
            editingModel = nil
            confirmation = nil
            let count = try queryManager.deleteAllModels()
            presentCompletionAlert("Successfully deleted \(count) models")
        } catch {
            presentCompletionAlert("Failed to delete all models: \(error.localizedDescription)")
        }
    }

    private func presentCompletionAlert(_ message: String) {
        completionMessage = message
        showCompletionAlert = true
    }
}
