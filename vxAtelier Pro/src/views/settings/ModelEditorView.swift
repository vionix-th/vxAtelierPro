import SwiftUI
import SwiftData

// MARK: - Model Editor View
struct ModelEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    
    let model: ModelItem
    @State private var name: String
    @State private var provider: String
    @State private var contextSize: Int
    @State private var capabilities: [ModelCapability]
    @State private var selectedEndpointFamilyRaw: String
    
    init(model: ModelItem) {
        self.model = model
        _name = State(initialValue: model.name)
        _provider = State(initialValue: model.provider)
        _contextSize = State(initialValue: model.contextSize)
        _capabilities = State(initialValue: model.capabilities)
        _selectedEndpointFamilyRaw = State(
            initialValue: model.endpointFamiliesRaw.first ?? LLMEndpointFamily.chatCompletions.rawValue
        )
    }

    private var endpointFamilies: [LLMEndpointFamily] {
        let families = model.endpointFamiliesRaw.compactMap { LLMEndpointFamily(rawValue: $0) }.filter { $0 != .models }
        return families.isEmpty ? [.chatCompletions] : families
    }

    private var selectedEndpointFamily: LLMEndpointFamily {
        LLMEndpointFamily(rawValue: selectedEndpointFamilyRaw) ?? endpointFamilies.first ?? .chatCompletions
    }

    private var selectedEndpointMappings: [ModelParameterMappingItem] {
        model.parameterMappings
            .filter { $0.endpointFamilyEnum == selectedEndpointFamily }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var addableParameterIDs: [LLMApplicationParameterID] {
        let existing = Set(selectedEndpointMappings.map(\.semanticParameterIDEnum))
        return LLMApplicationParameterID.allCases
            .filter { $0.isEditableMappingParameter && !existing.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Model Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .rounded))
                    
                    Picker("Provider", selection: $provider) {
                        ForEach([
                            ModelProviderUtils.Provider.openAI.rawValue,
                            ModelProviderUtils.Provider.anthropic.rawValue,
                            ModelProviderUtils.Provider.google.rawValue,
                            ModelProviderUtils.Provider.meta.rawValue,
                            ModelProviderUtils.Provider.mistral.rawValue,
                            ModelProviderUtils.Provider.xAI.rawValue,
                            ModelProviderUtils.Provider.deepSeek.rawValue,
                            ModelProviderUtils.Provider.custom.rawValue
                        ], id: \.self) { provider in
                            Text(provider)
                                .font(.system(.body, design: .rounded))
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
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
                        ForEach(ModelCapability.allCases.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { capability in
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
                                    Text(capability.rawValue)
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
                        Picker("Endpoint", selection: $selectedEndpointFamilyRaw) {
                            ForEach(endpointFamilies) { family in
                                Text(family.displayName).tag(family.rawValue)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Button {
                                LLMParameterMappingCatalog.resetDefaults(on: model, endpointFamily: selectedEndpointFamily)
                            } label: {
                                Label("Reset Endpoint Defaults", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)

                            Menu {
                                ForEach(addableParameterIDs) { parameterID in
                                    Button(parameterID.displayName) {
                                        addMapping(parameterID)
                                    }
                                }
                            } label: {
                                Label("Add Parameter", systemImage: "plus")
                            }
                            .disabled(addableParameterIDs.isEmpty)
                        }

                        if selectedEndpointMappings.isEmpty {
                            Text("No parameters configured for this endpoint.")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            VStack(spacing: AppDefaults.paddingSmall) {
                                ForEach(selectedEndpointMappings) { mapping in
                                    ModelParameterMappingRow(mapping: mapping)
                                    if mapping.id != selectedEndpointMappings.last?.id {
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
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                LLMParameterMappingCatalog.materializeDefaults(on: model, preserveCustomized: true)
                if !endpointFamilies.contains(where: { $0.rawValue == selectedEndpointFamilyRaw }) {
                    selectedEndpointFamilyRaw = endpointFamilies.first?.rawValue ?? LLMEndpointFamily.chatCompletions.rawValue
                }
            }
        }
    }
    
    private func save() {
        model.name = name
        model.modelID = name
        model.displayName = name
        model.provider = provider
        model.providerID = LLMProviderRegistry.providerID(fromProviderName: provider).rawValue
        model.contextSize = contextSize
        model.capabilities = capabilities
        LLMParameterMappingCatalog.materializeDefaults(on: model, preserveCustomized: true)
        
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

    private func addMapping(_ parameterID: LLMApplicationParameterID) {
        let mapping = ModelParameterMappingItem(
            endpointFamily: selectedEndpointFamily,
            semanticParameterID: parameterID,
            isEnabled: true,
            isRequired: false,
            encodingKind: .scalarKey,
            wireKey: parameterID.rawValue,
            isCustomized: true
        )
        model.parameterMappings.append(mapping)
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

                Toggle("Enabled", isOn: binding(\.isEnabled))
                    .toggleStyle(.switch)

                Toggle("Required", isOn: binding(\.isRequired))
                    .toggleStyle(.switch)

                Picker("Encoding", selection: Binding(
                    get: { mapping.encodingKind },
                    set: {
                        mapping.encodingKind = $0
                        mapping.markCustomized()
                    }
                )) {
                    ForEach(ModelParameterEncodingKind.allCases) { kind in
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
                        ForEach(ModelParameterStructuredPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text("Omitted from request")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextField("Default", text: Binding(
                    get: { defaultValueText },
                    set: { defaultValueText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            }
        }
        .padding(.vertical, AppDefaults.paddingSmall)
    }

    private var defaultValueText: String {
        get { mapping.defaultJSONValue?.stringValue ?? "" }
        nonmutating set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                mapping.defaultJSONValue = nil
            } else {
                switch mapping.semanticParameterIDEnum.valueType {
                case .integer:
                    mapping.defaultJSONValue = .integer(Int(trimmed) ?? 0)
                case .float:
                    mapping.defaultJSONValue = .number(Double(trimmed) ?? 0)
                case .boolean:
                    mapping.defaultJSONValue = .boolean(trimmed.lowercased() == "true")
                case .string:
                    mapping.defaultJSONValue = .string(trimmed)
                }
            }
            mapping.markCustomized()
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<ModelParameterMappingItem, Bool>) -> Binding<Bool> {
        Binding(
            get: { mapping[keyPath: keyPath] },
            set: {
                mapping[keyPath: keyPath] = $0
                mapping.markCustomized()
            }
        )
    }
}
