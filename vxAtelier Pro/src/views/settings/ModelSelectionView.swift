import SwiftData
import SwiftUI

/// A sheet view for selecting AI models from a list of available models.
/// Designed to be reused across the application where model selection is needed.
struct ModelSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ModelItem.name)]) private var allModels: [ModelItem]
    
    /// The currently selected model (used for display purposes)
    let selectedModel: String
    
    /// Callback that will be invoked when a model is selected
    let onModelSelected: (String) -> Void
    
    /// The current API configuration to filter models by
    let apiConfiguration: APIConfigurationItem?

    var fallbackModels: [ModelItem]? = nil
    
    /// Toggle to show all models or just those from the current provider
    @State private var showAllModels = false
    
    /// Search text for filtering models
    @State private var searchText = ""
    
    /// Selected model metadata filters.
    @State private var selectedModalities: Set<LLMModality> = []
    @State private var selectedSchemaFeatures: Set<LLMSchemaFeature> = []
    
    /// Filtered models based on current provider, showAllModels setting, and search text
    private var filteredModels: [ModelItem] {
        var models = allModels

        if let apiConfiguration {
            if !showAllModels {
                models = models.filter { $0.apiConfiguration?.id == apiConfiguration.id }
                if models.isEmpty, let fallback = fallbackModels {
                    models = fallback
                }
            }
        } else if !showAllModels {
            models = models.filter { $0.apiConfiguration == nil }
        }
        
        // Filter by selected metadata values; all selected filters must match.
        if !selectedModalities.isEmpty || !selectedSchemaFeatures.isEmpty {
            models = models.filter { model in
                selectedModalities.isSubset(of: Set(model.modalityEnums))
                    && selectedSchemaFeatures.isSubset(of: Set(model.schemaFeatureEnums))
            }
        }
        
        // Fulltext search: name, provider, modalities, and schema features.
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            models = models.filter { model in
                model.name.lowercased().contains(lowercasedSearch) ||
                model.provider.lowercased().contains(lowercasedSearch) ||
                model.metadataSearchTerms.map { $0.lowercased() }.contains(where: { $0.contains(lowercasedSearch) })
            }
        }
        
        return models
    }
    
    /// Group models by provider for better organization
    private var groupedModels: [String: [ModelItem]] {
        Dictionary(grouping: filteredModels) { model in
            if let config = model.apiConfiguration {
                return config.name
            }
            return "\(model.provider.capitalized) (Unassigned)"
        }
    }
    
    /// Sorted provider keys to ensure consistent order
    private var sortedProviders: [String] {
        groupedModels.keys.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and search
            VStack(spacing: 12) {
                Text("Select Model")
                    .font(.headline)
                    .padding(.top)
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search models", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                
                // Model metadata filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LLMModality.allCases.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { modality in
                            MetadataChip(
                                title: modality.displayName,
                                systemName: modality.systemName,
                                isSelected: selectedModalities.contains(modality),
                                onTap: {
                                    if selectedModalities.contains(modality) {
                                        selectedModalities.remove(modality)
                                    } else {
                                        selectedModalities.insert(modality)
                                    }
                                }
                            )
                        }
                        ForEach(LLMSchemaFeature.allCases.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { feature in
                            MetadataChip(
                                title: feature.displayName,
                                systemName: feature.systemName,
                                isSelected: selectedSchemaFeatures.contains(feature),
                                onTap: {
                                    if selectedSchemaFeatures.contains(feature) {
                                        selectedSchemaFeatures.remove(feature)
                                    } else {
                                        selectedSchemaFeatures.insert(feature)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                
                Toggle("Show All Models", isOn: $showAllModels)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                
                Divider()
            }
            
            // Models list
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
                        // Group models by provider
                        ForEach(sortedProviders, id: \.self) { provider in
                            if let models = groupedModels[provider] {
                                VStack(alignment: .leading, spacing: 0) {
                                    // Provider header
                                    if showAllModels {
                                        HStack {
                                            Text(provider)
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
                                    
                                    // Models in this provider group
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
                                
                                if provider != sortedProviders.last {
                                    Divider()
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // Footer with cancel button
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

/// Individual row view for a model
struct ModelRowView: View {
    let model: ModelItem
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)
                    
                    // Provider info as subtitle
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
            
            // Metadata row
            if model.contextSize > 0 || !model.modalityEnums.isEmpty || !model.schemaFeatureEnums.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Context size info if available
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
                        ForEach(model.modalityEnums, id: \.self) { modality in
                            HStack(spacing: 4) {
                                Image(systemName: modality.systemName)
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text(modality.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                            .help(modality.displayName)
                        }
                        ForEach(model.schemaFeatureEnums, id: \.self) { feature in
                            HStack(spacing: 4) {
                                Image(systemName: feature.systemName)
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text(feature.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                            .help(feature.displayName)
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
    
    /// Format token count in a readable way (e.g., "8K", "32K", etc.)
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000)K"
        } else {
            return "\(count)"
        }
    }
}

/// A chip-style button for selecting model metadata filters.
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
