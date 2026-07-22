import SwiftData
import SwiftUI

private struct MappingOverrideDraft: Identifiable {
    var id: String { "\(adapterID.rawValue):\(parameterID.rawValue)" }
    var adapterID: LLMAdapterID
    var parameterID: LLMParameterID
    var encodingKind: LLMParameterEncodingKind
    var wireKey: String
    var structuredPreset: LLMParameterStructuredPreset?

    init(_ item: ModelParameterMappingOverrideItem) {
        adapterID = item.adapterID
        parameterID = item.parameterID
        encodingKind = item.encodingKind
        wireKey = item.wireKey
        structuredPreset = item.structuredPreset
    }

    var mapping: LLMParameterMapping {
        LLMParameterMapping(
            adapterID: adapterID,
            parameterID: parameterID,
            encodingKind: encodingKind,
            wireKey: wireKey,
            structuredPreset: structuredPreset
        )
    }
}

private struct ParameterOverrideDraft: Identifiable {
    var id: String { "\(adapterID.rawValue):\(parameterID.rawValue)" }
    var adapterID: LLMAdapterID
    var parameterID: LLMParameterID
    var support: LLMSupportState?
    var required: Bool?
    var enabledByDefault: Bool?
    var defaultValueKind: ModelDefaultValueOverrideKind
    var defaultValueText: String

    init(_ item: ModelParameterOverrideItem) {
        adapterID = item.adapterID
        parameterID = item.parameterID
        support = item.support
        required = item.requiredOverride
        enabledByDefault = item.enabledByDefaultOverride
        defaultValueKind = item.defaultValueOverrideKind
        if let value = item.defaultValue,
           let data = try? JSONEncoder().encode(value) {
            defaultValueText = String(data: data, encoding: .utf8) ?? ""
        } else {
            defaultValueText = ""
        }
    }
}

struct ModelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]

    let model: ModelItem
    @State private var modelID: String
    @State private var selectedConfigurationID: PersistentIdentifier?
    @State private var displayNameOverride: String
    @State private var contextSizeOverride: String
    @State private var capabilityOverrides: [LLMModelCapability: LLMSupportState]
    @State private var mappingOverrides: [MappingOverrideDraft]
    @State private var parameterOverrides: [ParameterOverrideDraft]
    @State private var errorMessage = ""
    @State private var showError = false

    init(model: ModelItem) {
        self.model = model
        _modelID = State(initialValue: model.modelID)
        _selectedConfigurationID = State(initialValue: model.apiConfiguration?.persistentModelID)
        _displayNameOverride = State(initialValue: model.displayNameOverride ?? "")
        _contextSizeOverride = State(initialValue: model.contextSizeOverride.map(String.init) ?? "")
        _capabilityOverrides = State(initialValue: Dictionary(uniqueKeysWithValues: model.capabilityOverrides.map {
            ($0.capability, $0.support)
        }))
        _mappingOverrides = State(initialValue: model.parameterMappingOverrides.map(MappingOverrideDraft.init))
        _parameterOverrides = State(initialValue: model.parameterOverrides.map(ParameterOverrideDraft.init))
    }

    private var selectedConfiguration: APIConfigurationItem? {
        apiConfigurations.first { $0.persistentModelID == selectedConfigurationID }
    }

    private var selectedAdapterID: LLMAdapterID {
        selectedConfiguration?.defaultAdapterIDEnum ?? model.adapterID
    }

    private var draftProfile: LLMModelProfile {
        let mappings = mappingOverrides
            .filter { $0.adapterID == selectedAdapterID }
            .reduce(into: [LLMParameterID: LLMParameterMapping]()) { $0[$1.parameterID] = $1.mapping }
        let parameterSettings = parameterOverrides
            .filter { $0.adapterID == selectedAdapterID }
            .reduce(into: [LLMParameterID: LLMParameterOverrides]()) {
                $0[$1.parameterID] = overrides(from: $1, validateValue: false)
            }
        return LLMModelProfileResolver(fallbackContextSize: AppDefaults.ModelContextSizes.defaultSize).resolve(
            providerID: selectedConfiguration?.providerIDEnum ?? model.providerID,
            adapterID: selectedAdapterID,
            modelID: modelID,
            metadata: model.providerMetadata,
            overrides: LLMModelOverrides(
                displayName: displayNameOverride,
                contextSize: Int(contextSizeOverride),
                capabilitySupport: capabilityOverrides,
                parameterMappings: mappings,
                parameterOverrides: parameterSettings
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Model ID", text: $modelID)
                    Picker("API Configuration", selection: $selectedConfigurationID) {
                        ForEach(apiConfigurations) { configuration in
                            Text(configuration.name).tag(Optional(configuration.persistentModelID))
                        }
                    }
                    TextField("Display name override", text: $displayNameOverride)
                    TextField("Context size override", text: $contextSizeOverride)
                    LabeledContent("Resolved name", value: draftProfile.displayName)
                    LabeledContent("Resolved context", value: draftProfile.contextSize.formatted())
                }

                Section {
                    ForEach(LLMModelCapability.allCases) { capability in
                        HStack {
                            Label(capability.displayName, systemImage: capability.systemName)
                            Spacer()
                            Text([
                                draftProfile.capabilities[capability]?.state.displayName ?? "Unknown",
                                draftProfile.capabilities[capability]?.source.displayName ?? "Fallback"
                            ].joined(separator: " · "))
                                .foregroundStyle(.secondary)
                            Picker("Override", selection: capabilityOverrideBinding(capability)) {
                                Text("Inherit").tag(LLMSupportState?.none)
                                Text("Supported").tag(Optional(LLMSupportState.supported))
                                Text("Unsupported").tag(Optional(LLMSupportState.unsupported))
                            }
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Capabilities")
                } footer: {
                    Text("Support is advisory for remote providers. Overrides affect presentation and defaults, not request admission.")
                }

                Section("Parameter Profile") {
                    ForEach(LLMParameterID.allCases.filter(\.isProviderMappable)) { parameterID in
                        let profile = draftProfile.parameters[parameterID]
                        HStack {
                            VStack(alignment: .leading) {
                                Text(AiParameterPresentationCatalog.displayName(for: parameterID))
                                Text([
                                    profile?.support.state.displayName ?? "Unknown",
                                    profile?.support.source.displayName ?? "Fallback",
                                    profile?.mapping?.encodingKind == .disabled || profile?.mapping == nil ? "Unencodable" : "Mapped"
                                ].joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu("Override") {
                                Button("Parameter settings") { addParameterOverride(parameterID) }
                                Button("Wire mapping") { addMappingOverride(parameterID) }
                            }
                        }
                    }
                }

                if !mappingOverrides.isEmpty {
                    Section("Mapping Overrides") {
                        ForEach($mappingOverrides) { $draft in
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(AiParameterPresentationCatalog.displayName(for: draft.parameterID))
                                    Spacer()
                                    Button(role: .destructive) {
                                        mappingOverrides.removeAll { $0.id == draft.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                Picker("Encoding", selection: $draft.encodingKind) {
                                    ForEach(LLMParameterEncodingKind.allCases) { kind in
                                        Text(kind.displayName).tag(kind)
                                    }
                                }
                                if draft.encodingKind == .scalarKey {
                                    TextField("Wire key", text: $draft.wireKey)
                                }
                                if draft.encodingKind == .structuredPreset {
                                    Picker("Preset", selection: $draft.structuredPreset) {
                                        Text("None").tag(LLMParameterStructuredPreset?.none)
                                        ForEach(LLMParameterStructuredPreset.allCases) { preset in
                                            Text(preset.displayName).tag(Optional(preset))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !parameterOverrides.isEmpty {
                    Section("Parameter Overrides") {
                        ForEach($parameterOverrides) { $draft in
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(AiParameterPresentationCatalog.displayName(for: draft.parameterID))
                                    Spacer()
                                    Button(role: .destructive) {
                                        parameterOverrides.removeAll { $0.id == draft.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                Picker("Support", selection: $draft.support) {
                                    Text("Inherit").tag(LLMSupportState?.none)
                                    Text("Supported").tag(Optional(LLMSupportState.supported))
                                    Text("Unsupported").tag(Optional(LLMSupportState.unsupported))
                                }
                                Picker("Required", selection: $draft.required) {
                                    Text("Inherit").tag(Bool?.none)
                                    Text("Required").tag(Optional(true))
                                    Text("Optional").tag(Optional(false))
                                }
                                Picker("Default activation", selection: $draft.enabledByDefault) {
                                    Text("Inherit").tag(Bool?.none)
                                    Text("Enabled").tag(Optional(true))
                                    Text("Disabled").tag(Optional(false))
                                }
                                Picker("Default value", selection: $draft.defaultValueKind) {
                                    Text("Inherit").tag(ModelDefaultValueOverrideKind.inherit)
                                    Text("Override").tag(ModelDefaultValueOverrideKind.value)
                                    Text("No default").tag(ModelDefaultValueOverrideKind.none)
                                }
                                if draft.defaultValueKind == .value {
                                    TextField("JSON value", text: $draft.defaultValueText)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(model.modelContext == nil ? "Add Model" : "Edit Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedConfiguration == nil)
                }
            }
            .alert("Model Profile", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func capabilityOverrideBinding(_ capability: LLMModelCapability) -> Binding<LLMSupportState?> {
        Binding(
            get: { capabilityOverrides[capability] },
            set: { capabilityOverrides[capability] = $0 }
        )
    }

    private func addMappingOverride(_ parameterID: LLMParameterID) {
        guard !mappingOverrides.contains(where: { $0.adapterID == selectedAdapterID && $0.parameterID == parameterID }) else { return }
        let resolved = draftProfile.parameters[parameterID]?.mapping
        mappingOverrides.append(MappingOverrideDraft(ModelParameterMappingOverrideItem(
            mapping: resolved ?? LLMParameterMapping(
                adapterID: selectedAdapterID,
                parameterID: parameterID,
                encodingKind: .scalarKey,
                wireKey: parameterID.rawValue
            )
        )))
    }

    private func addParameterOverride(_ parameterID: LLMParameterID) {
        guard !parameterOverrides.contains(where: { $0.adapterID == selectedAdapterID && $0.parameterID == parameterID }) else { return }
        parameterOverrides.append(ParameterOverrideDraft(ModelParameterOverrideItem(
            adapterID: selectedAdapterID,
            parameterID: parameterID
        )))
    }

    private func overrides(from draft: ParameterOverrideDraft, validateValue: Bool) -> LLMParameterOverrides {
        let defaultValue: LLMDefaultValueOverride
        switch draft.defaultValueKind {
        case .inherit:
            defaultValue = .inherit
        case .none:
            defaultValue = .none
        case .value:
            if let data = draft.defaultValueText.data(using: .utf8),
               let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                defaultValue = .value(value)
            } else {
                defaultValue = .inherit
                if validateValue {
                    errorMessage = "Default values must be valid JSON."
                    showError = true
                }
            }
        }
        return LLMParameterOverrides(
            support: draft.support,
            isRequired: draft.required,
            isEnabledByDefault: draft.enabledByDefault,
            defaultValue: defaultValue
        )
    }

    private func save() {
        guard let selectedConfiguration else { return }
        var parameterSettings: [(LLMAdapterID, LLMParameterID, LLMParameterOverrides)] = []
        for draft in parameterOverrides {
            let parameterOverrides = overrides(from: draft, validateValue: true)
            guard !showError else { return }
            parameterSettings.append((draft.adapterID, draft.parameterID, parameterOverrides))
        }
        do {
            try queryManager.updateModelProfile(
                model,
                modelID: modelID,
                apiConfiguration: selectedConfiguration,
                displayNameOverride: displayNameOverride,
                contextSizeOverride: Int(contextSizeOverride),
                capabilityOverrides: capabilityOverrides,
                mappingOverrides: mappingOverrides.map(\.mapping),
                parameterOverrides: parameterSettings
            )
            dismiss()
        } catch {
            vxAtelierPro.log.error("Failed to save model profile: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
