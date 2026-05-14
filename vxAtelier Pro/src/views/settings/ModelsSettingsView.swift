import SwiftData
import SwiftUI

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

    struct EditingModel: Identifiable {
        let id = UUID()
        var model: ModelItem
        var isNew: Bool
    }

    struct ModelRowItem: Identifiable {
        let model: ModelItem
        var id: PersistentIdentifier { model.persistentModelID }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredModels: [ModelRowItem] {
        models
            .filter(modelMatchesSearch)
            .sorted {
                let lhsProvider = $0.apiConfiguration?.name ?? ""
                let rhsProvider = $1.apiConfiguration?.name ?? ""
                if lhsProvider == rhsProvider {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhsProvider.localizedCaseInsensitiveCompare(rhsProvider) == .orderedAscending
            }
            .map(ModelRowItem.init)
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
                    editingModel = EditingModel(model: row.model, isNew: false)
                }
            ) { row in
                SettingsEntityRow(
                    title: row.model.name,
                    subtitle: row.model.apiConfiguration?.name ?? "No API Configuration",
                    metadata: "Provider: \(row.model.apiConfiguration?.providerIDEnum.displayName ?? "Unknown")  Context: \(row.model.contextSize)",
                    systemImages: row.model.metadataIconSystemNames
                )
            } actions: { row in
                [
                    SettingsEntityAction(title: "Edit", systemImage: "pencil") {
                        editingModel = EditingModel(model: row.model, isNew: false)
                    },
                    SettingsEntityAction(title: "Delete", systemImage: "trash", role: .destructive) {
                        confirmation = SettingsConfirmation(
                            title: "Delete Model",
                            message: "Delete \"\(row.model.name)\"? This action cannot be undone.",
                            confirmTitle: "Delete",
                            action: { deleteModel(row.model) }
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

    private func modelMatchesSearch(_ model: ModelItem) -> Bool {
        guard !normalizedSearchText.isEmpty else { return true }

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

    private func deleteModel(_ model: ModelItem) {
        do {
            try queryManager.delete(model)
        } catch {
            presentCompletionAlert("Failed to delete model: \(error.localizedDescription)")
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

    private func presentCompletionAlert(_ message: String) {
        completionMessage = message
        showCompletionAlert = true
    }
}
