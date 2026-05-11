import SwiftUI
import SwiftData

// MARK: - Model Editor View
struct ModelEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    
    let model: ModelItem
    @State private var name: String
    @State private var selectedConfigurationID: PersistentIdentifier?
    @State private var contextSize: Int
    @State private var capabilities: [LLMModelCapability]
    
    init(model: ModelItem) {
        self.model = model
        _name = State(initialValue: model.name)
        _selectedConfigurationID = State(initialValue: model.apiConfiguration?.persistentModelID)
        _contextSize = State(initialValue: model.contextSize)
        _capabilities = State(initialValue: model.capabilities)
    }

    private var selectedAdapterID: LLMAdapterID {
        selectedConfiguration?.defaultAdapterIDEnum ?? .openAIChatCompletions
    }

    private var selectedAdapterMappings: [ModelParameterMappingItem] {
        model.parameterMappings
            .filter { $0.adapterIDEnum == selectedAdapterID }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var selectedAdapterAvailability: [ModelParameterAvailabilityItem] {
        model.parameterAvailability
            .filter { $0.adapterIDEnum == selectedAdapterID }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var selectedConfiguration: APIConfigurationItem? {
        apiConfigurations.first { $0.persistentModelID == selectedConfigurationID }
    }

    private var addableParameterIDs: [LLMParameterID] {
        let existing = Set(selectedAdapterMappings.map(\.semanticParameterIDEnum))
        return LLMParameterID.allCases
            .filter { $0.isProviderMappable && !existing.contains($0) }
    }

    private var addableAvailabilityParameterIDs: [LLMParameterID] {
        let existing = Set(selectedAdapterAvailability.map(\.semanticParameterIDEnum))
        return LLMParameterID.allCases
            .filter { $0.isProviderMappable && !existing.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Model Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .rounded))

                    Picker("API Configuration", selection: $selectedConfigurationID) {
                        ForEach(apiConfigurations) { config in
                            Text(config.name)
                                .font(.system(.body, design: .rounded))
                                .tag(config.persistentModelID as PersistentIdentifier?)
                        }
                    }
                    .pickerStyle(.menu)

                    if let selectedConfiguration {
                        Text("Provider: \(selectedConfiguration.providerIDEnum.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No API configuration selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Model Information")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                        HStack(spacing: AppDefaults.paddingLarge) {
                            TextField("", value: $contextSize, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .monospacedDigit()
                            
                            Text("tokens")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .rounded))
                            
                            Spacer()
                            
                            Menu {
                                Group {
                                    Button("4K (4,096)") { contextSize = 4_096 }
                                    Button("8K (8,192)") { contextSize = 8_192 }
                                    Button("16K (16,384)") { contextSize = 16_384 }
                                }
                                Divider()
                                Group {
                                    Button("32K (32,768)") { contextSize = 32_768 }
                                    Button("128K (131,072)") { contextSize = 131_072 }
                                }
                            } label: {
                                Label("Presets", systemImage: "slider.horizontal.3")
                                    .font(.system(.body, design: .rounded))
                            }
                            .menuStyle(.borderlessButton)
                        }
                        .padding(.vertical, AppDefaults.paddingSmall)
                        
                        Text("Maximum number of tokens the model can process in a single request")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Context Size")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppDefaults.paddingLarge) {
                        ForEach(LLMModelCapability.allCases.sorted(by: { $0.displayName < $1.displayName })) { capability in
                            Toggle(isOn: Binding(
                                get: { capabilities.contains(capability) },
                                set: { isEnabled in
                                    if isEnabled {
                                        capabilities.append(capability)
                                    } else {
                                        capabilities.removeAll { $0 == capability }
                                    }
                                }
                            )) {
                                Label {
                                    Text(capability.displayName)
                                        .font(.system(.body, design: .rounded))
                                } icon: {
                                    Image(systemName: capability.systemName)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.vertical, AppDefaults.paddingSmall)
                        }
                    }
                } header: {
                    Text("Capabilities")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }

                Section {
                    VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                        Text("API Mode: \(selectedAdapterID.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button {
                                model.resetDefaultParameterMappings(adapterID: selectedAdapterID)
                            } label: {
                                Label("Reset Adapter Defaults", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)

                            Menu {
                                ForEach(addableParameterIDs) { parameterID in
                                    Button(AiParameterPresentationCatalog.displayName(for: parameterID)) {
                                        addMapping(parameterID)
                                    }
                                }
                            } label: {
                                Label("Add Parameter", systemImage: "plus")
                            }
                            .disabled(addableParameterIDs.isEmpty)
                        }

                        if selectedAdapterMappings.isEmpty {
                            Text("No parameters configured for this adapter.")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            VStack(spacing: AppDefaults.paddingSmall) {
                                ForEach(selectedAdapterMappings) { mapping in
                                    ModelParameterMappingRow(mapping: mapping)
                                    if mapping.id != selectedAdapterMappings.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppDefaults.paddingSmall)
                } header: {
                    Text("Parameter Translation")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }

                Section {
                    VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                        Text("API Mode: \(selectedAdapterID.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button {
                                model.resetDefaultParameterAvailability(adapterID: selectedAdapterID)
                            } label: {
                                Label("Reset Availability Defaults", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)

                            Menu {
                                ForEach(addableAvailabilityParameterIDs) { parameterID in
                                    Button(AiParameterPresentationCatalog.displayName(for: parameterID)) {
                                        addAvailability(parameterID)
                                    }
                                }
                            } label: {
                                Label("Add Availability", systemImage: "plus")
                            }
                            .disabled(addableAvailabilityParameterIDs.isEmpty)
                        }

                        if selectedAdapterAvailability.isEmpty {
                            Text("No parameter availability configured for this adapter.")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            VStack(spacing: AppDefaults.paddingSmall) {
                                ForEach(selectedAdapterAvailability) { availability in
                                    ModelParameterAvailabilityRow(availability: availability)
                                    if availability.id != selectedAdapterAvailability.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppDefaults.paddingSmall)
                } header: {
                    Text("Parameter Availability")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
                
                if model.modelContext != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteModel()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Model")
                            }
                            .frame(maxWidth: .infinity)
                            .font(.system(.body, design: .rounded))
                        }
                        .buttonStyle(.bordered)
                        .padding(.vertical, AppDefaults.paddingSmall)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(model.modelContext == nil ? "Add Model" : "Edit Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(.body, design: .rounded))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(.body, design: .rounded))
                        .disabled(name.isEmpty || selectedConfiguration == nil)
                }
            }
            .onAppear {
                if selectedConfigurationID == nil {
                    selectedConfigurationID = model.apiConfiguration?.persistentModelID ?? apiConfigurations.first?.persistentModelID
                }
            }
            .onChange(of: selectedConfigurationID) { _, _ in
                applyCatalogDefaultsForSelectedConfiguration()
            }
        }
    }
    
    private func save() {
        guard let selectedConfiguration else { return }
        model.modelID = name
        model.displayName = name
        model.apiConfiguration = selectedConfiguration
        model.contextSize = contextSize
        model.capabilitiesRaw = capabilities.map(\.rawValue)
        model.materializeDefaultParameterMappings(preserveCustomized: true)
        model.materializeDefaultParameterAvailability(preserveCustomized: true)
        
        do {
            if model.modelContext == nil {
                try queryManager.insert(model)
            } else {
                // If the model already exists, just save the context
                // The insert method already calls saveContext
                try queryManager.saveContext()
            }
            // queryManager.refresh() // Refresh QueryManager after save (already done by insert/saveContext)
            dismiss()
        } catch {
            vxAtelierPro.log.error("Failed to save model \(name): \(error.localizedDescription)")
            // Optionally show an alert to the user here
        }
    }
    
    private func deleteModel() {
        do {
            try queryManager.delete(model)
            // queryManager.refresh() // Refresh QueryManager after delete (already done by delete)
            dismiss()
        } catch {
            vxAtelierPro.log.error("Failed to delete model \(model.name): \(error.localizedDescription)")
            // Optionally show an alert to the user here
        }
    }

    private func applyCatalogDefaultsForSelectedConfiguration() {
        guard let selectedConfiguration else { return }
        let candidate = LLMModelDescriptorResolver().catalogDescriptor(
            for: name,
            providerID: selectedConfiguration.providerIDEnum
        )
        contextSize = candidate.contextWindow ?? AppDefaults.ModelContextSizes.defaultSize
        capabilities = candidate.capabilities
    }

    private func addMapping(_ parameterID: LLMParameterID) {
        let mapping = ModelParameterMappingItem(
            adapterID: selectedAdapterID,
            semanticParameterID: parameterID,
            encodingKind: .scalarKey,
            wireKey: parameterID.rawValue,
            isCustomized: true
        )
        model.parameterMappings.append(mapping)
    }

    private func addAvailability(_ parameterID: LLMParameterID) {
        let availability = ModelParameterAvailabilityItem(
            adapterID: selectedAdapterID,
            semanticParameterID: parameterID,
            isAvailable: true,
            isRequired: false,
            isIncludedByDefault: false,
            isCustomized: true
        )
        model.parameterAvailability.append(availability)
    }
}

private struct ModelParameterMappingRow: View {
    @Bindable var mapping: ModelParameterMappingItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
            HStack(alignment: .center, spacing: AppDefaults.paddingMedium) {
                Text(mapping.displayName)
                    .frame(width: 150, alignment: .leading)
                    .help(mapping.paramDescription)

                Picker("Encoding", selection: Binding(
                    get: { mapping.encodingKind },
                    set: {
                        mapping.encodingKind = $0
                        mapping.markCustomized()
                    }
                )) {
                    ForEach(LLMParameterEncodingKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: AppDefaults.paddingMedium) {
                if mapping.encodingKind == .scalarKey {
                    TextField("Wire Key", text: Binding(
                        get: { mapping.wireKey },
                        set: {
                            mapping.wireKey = $0
                            mapping.markCustomized()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                } else if mapping.encodingKind == .structuredPreset {
                    Picker("Preset", selection: Binding(
                        get: { mapping.structuredPreset ?? .openAIChatResponseFormat },
                        set: {
                            mapping.structuredPreset = $0
                            mapping.markCustomized()
                        }
                    )) {
                        ForEach(LLMParameterStructuredPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text("Omitted from request")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, AppDefaults.paddingSmall)
    }
}

private struct ModelParameterAvailabilityRow: View {
    @Bindable var availability: ModelParameterAvailabilityItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
            HStack(alignment: .center, spacing: AppDefaults.paddingMedium) {
                Text(availability.displayName)
                    .frame(width: 150, alignment: .leading)
                    .help(availability.paramDescription)

                Toggle("Available", isOn: binding(\.isAvailable))
                    .toggleStyle(.switch)

                Toggle("Required", isOn: binding(\.isRequired))
                    .toggleStyle(.switch)

                Toggle("Included by Default", isOn: binding(\.isIncludedByDefault))
                    .toggleStyle(.switch)
            }

            HStack(spacing: AppDefaults.paddingMedium) {
                TextField("Default", text: Binding(
                    get: { defaultValueText },
                    set: { defaultValueText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

                Text("Leave empty for no model default value.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, AppDefaults.paddingSmall)
    }

    private var defaultValueText: String {
        get { availability.defaultJSONValue?.stringValue ?? "" }
        nonmutating set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                availability.defaultJSONValue = nil
            } else {
                switch availability.semanticParameterIDEnum.valueType {
                case .integer:
                    availability.defaultJSONValue = .integer(Int(trimmed) ?? 0)
                case .float:
                    availability.defaultJSONValue = .number(Double(trimmed) ?? 0)
                case .boolean:
                    availability.defaultJSONValue = .boolean(trimmed.lowercased() == "true")
                case .string:
                    availability.defaultJSONValue = .string(trimmed)
                }
            }
            availability.markCustomized()
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<ModelParameterAvailabilityItem, Bool>) -> Binding<Bool> {
        Binding(
            get: { availability[keyPath: keyPath] },
            set: {
                availability[keyPath: keyPath] = $0
                availability.markCustomized()
            }
        )
    }
}
