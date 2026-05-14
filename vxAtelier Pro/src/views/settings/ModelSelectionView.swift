import SwiftData
import SwiftUI

/// Selects a persisted model for runtime flows or a draft candidate for API configuration editing.
struct ModelSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ModelItem.modelID)]) private var allModels: [ModelItem]

    let selectedModel: String
    let onModelSelected: (String) -> Void
    let apiConfiguration: APIConfigurationItem?
    var draftModelCandidates: [LLMModelDescriptor]? = nil

    @State private var showAllModels = false
    @State private var searchText = ""
    @State private var selectedCapabilities: Set<LLMModelCapability> = []

    private var isDraftMode: Bool {
        draftModelCandidates != nil
    }

    private var filteredModels: [ModelSelectionOption] {
        var models: [ModelSelectionOption]
        if let draftModelCandidates {
            models = draftModelCandidates.map {
                ModelSelectionOption(descriptor: $0, groupName: apiConfiguration?.name ?? $0.providerID.displayName)
            }
        } else if let apiConfiguration, !showAllModels {
            models = allModels
                .filter { $0.apiConfiguration?.id == apiConfiguration.id }
                .map(ModelSelectionOption.init(model:))
        } else {
            models = allModels.map(ModelSelectionOption.init(model:))
        }

        if !selectedCapabilities.isEmpty {
            models = models.filter { selectedCapabilities.isSubset(of: Set($0.capabilities)) }
        }

        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            models = models.filter { model in
                model.name.lowercased().contains(lowercasedSearch)
                    || model.groupName.lowercased().contains(lowercasedSearch)
                    || model.metadataSearchTerms.map { $0.lowercased() }.contains { $0.contains(lowercasedSearch) }
            }
        }

        return models
    }

    private var groupedModels: [String: [ModelSelectionOption]] {
        Dictionary(grouping: filteredModels) { $0.groupName }
    }

    private var sortedGroups: [String] {
        groupedModels.keys.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Select Model")
                    .font(.headline)
                    .padding(.top)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search models", text: $searchText)
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
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LLMModelCapability.allCases.sorted(by: { $0.displayName < $1.displayName })) { capability in
                            MetadataChip(
                                title: capability.displayName,
                                systemName: capability.systemName,
                                isSelected: selectedCapabilities.contains(capability)
                            ) {
                                if selectedCapabilities.contains(capability) {
                                    selectedCapabilities.remove(capability)
                                } else {
                                    selectedCapabilities.insert(capability)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                if !isDraftMode {
                    Toggle("Show All Models", isOn: $showAllModels)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                Divider()
            }

            if filteredModels.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "questionmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No models found")
                        .font(.headline)
                    if !searchText.isEmpty {
                        Text("Try adjusting your search or filters")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sortedGroups, id: \.self) { group in
                            if let models = groupedModels[group] {
                                VStack(alignment: .leading, spacing: 0) {
                                    if showAllModels || isDraftMode {
                                        HStack {
                                            Text(group)
                                                .font(.headline)
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal)
                                                .padding(.vertical, 8)

                                            Spacer()

                                            Text("\(models.count)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .padding(.trailing)
                                        }
                                        .background(Color.secondary.opacity(0.1))
                                    }

                                    ForEach(models) { model in
                                        ModelRowView(
                                            model: model,
                                            isSelected: model.name == selectedModel,
                                            onSelect: {
                                                vxAtelierPro.log.info("Selected model '\(model.name)'")
                                                onModelSelected(model.name)
                                                dismiss()
                                            }
                                        )

                                        if model.id != models.last?.id {
                                            Divider()
                                                .padding(.leading, 16)
                                        }
                                    }
                                }

                                if group != sortedGroups.last {
                                    Divider()
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            VStack {
                Divider()

                Button("Cancel") {
                    vxAtelierPro.log.debug("Cancelled model selection")
                    dismiss()
                }
                .padding()
            }
        }
        .frame(idealWidth: 500, idealHeight: 500)
        .onAppear {
            vxAtelierPro.log.debug("Model selection sheet appeared")
        }
    }
}

/// Display model record used by the picker and search results.
private struct ModelSelectionOption: Identifiable {
    let id: String
    let name: String
    let provider: String
    let contextSize: Int
    let capabilities: [LLMModelCapability]
    let metadataSearchTerms: [String]
    let groupName: String
    let apiConfigurationID: PersistentIdentifier?

    init(model: ModelItem) {
        self.id = String(describing: model.persistentModelID)
        self.name = model.modelID
        self.provider = model.apiConfiguration?.providerIDEnum.displayName ?? "Unknown Provider"
        self.contextSize = model.contextSize
        self.capabilities = model.capabilities
        self.metadataSearchTerms = model.metadataSearchTerms
        self.groupName = model.apiConfiguration?.name ?? "Unassigned"
        self.apiConfigurationID = model.apiConfiguration?.id
    }

    init(descriptor: LLMModelDescriptor, groupName: String) {
        self.id = "descriptor-\(descriptor.providerID.rawValue)-\(descriptor.id)"
        self.name = descriptor.id
        self.provider = descriptor.providerID.displayName
        self.contextSize = descriptor.contextWindow ?? 0
        self.capabilities = descriptor.capabilities
        self.metadataSearchTerms = descriptor.capabilities.map(\.displayName)
        self.groupName = groupName
        self.apiConfigurationID = nil
    }
}

/// Selectable row for a model option.
private struct ModelRowView: View {
    let model: ModelSelectionOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)

                    Text(model.provider)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }

            if model.contextSize > 0 || !model.capabilities.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if model.contextSize > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "character.textbox")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text(formatTokenCount(model.contextSize))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                            .help("Context window size")
                        }

                        ForEach(model.capabilities) { capability in
                            HStack(spacing: 4) {
                                Image(systemName: capability.systemName)
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text(capability.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                            .help(capability.displayName)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .onTapGesture(perform: onSelect)
    }

    private func formatTokenCount(_ count: Int) -> String {
        count >= 1000 ? "\(count / 1000)K" : "\(count)"
    }
}

/// Toggle chip used to filter model capabilities.
private struct MetadataChip: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, AppDefaults.paddingMedium)
            .padding(.vertical, AppDefaults.paddingSmall)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? Color.accentColor : Color.primary)
            .cornerRadius(AppDefaults.cornerRadiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
