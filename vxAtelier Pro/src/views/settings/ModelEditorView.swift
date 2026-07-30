import SwiftData
import SwiftUI

private struct ParameterOverrideDraft: Identifiable {
    var id: String { "\(adapterID.rawValue):\(parameterID.rawValue)" }
    var adapterID: LLMAdapterID
    var parameterID: LLMParameterID
    var support: LLMSupportState?
    var encodingKind: LLMParameterEncodingKind?
    var wireKey: String
    var structuredPreset: LLMParameterStructuredPreset?
    var required: Bool?
    var enabledByDefault: Bool?
    var defaultValueKind: ModelDefaultValueOverrideKind
    var defaultValueText: String
    var optionsKind: ModelDefaultValueOverrideKind
    var optionsText: String

    init(_ item: ModelParameterOverrideItem) {
        adapterID = item.adapterID
        parameterID = item.parameterID
        support = item.support
        encodingKind = item.encodingKind
        wireKey = item.wireKey ?? ""
        structuredPreset = item.structuredPreset
        required = item.requiredOverride
        enabledByDefault = item.enabledByDefaultOverride
        defaultValueKind = item.defaultValueOverrideKind
        if let value = item.defaultValue,
           let data = try? JSONEncoder().encode(value) {
            defaultValueText = String(data: data, encoding: .utf8) ?? ""
        } else {
            defaultValueText = ""
        }
        optionsKind = item.optionsOverrideKind
        optionsText = item.options?.joined(separator: ", ") ?? ""
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
        _parameterOverrides = State(initialValue: model.parameterOverrides.map(ParameterOverrideDraft.init))
    }

    private var selectedConfiguration: APIConfigurationItem? {
        apiConfigurations.first { $0.persistentModelID == selectedConfigurationID }
    }

    private var selectedAdapterID: LLMAdapterID {
        selectedConfiguration?.parsedAdapterID ?? model.adapterID
    }

    private var draftProfile: LLMModelProfile {
        let settings = parameterOverrides
            .filter { $0.adapterID == selectedAdapterID }
            .reduce(into: [LLMParameterID: LLMParameterOverrides]()) {
                $0[$1.parameterID] = overrides(from: $1, validateValue: false)
            }
        return LLMModelProfileResolver(fallbackContextSize: AppDefaults.ModelContextSizes.defaultSize).resolve(
            providerID: selectedConfiguration?.parsedProviderID ?? model.providerID,
            adapterID: selectedAdapterID,
            modelID: modelID,
            metadata: model.providerMetadata,
            overrides: LLMModelOverrides(
                displayName: displayNameOverride,
                contextSize: Int(contextSizeOverride),
                capabilitySupport: capabilityOverrides,
                parameterOverrides: settings
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
                    Text("Capability metadata is advisory for remote providers.")
                }

                Section {
                    ForEach(LLMParameterID.allCases) { parameterID in
                        let profile = draftProfile.parameters[parameterID]
                        HStack {
                            VStack(alignment: .leading) {
                                Text(AiParameterPresentationCatalog.displayName(for: parameterID))
                                Text(parameterSummary(profile))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Override") {
                                addParameterOverride(parameterID)
                            }
                        }
                    }
                } header: {
                    Text("Resolved Parameter Profile")
                } footer: {
                    Text("Parameters inherit from the adapter API, provider rules, model rules, and provider observations.")
                }

                if !parameterOverrides.isEmpty {
                    Section {
                        ForEach($parameterOverrides) { $draft in
                            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
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
                                Picker("Mapping", selection: $draft.encodingKind) {
                                    Text("Inherit").tag(LLMParameterEncodingKind?.none)
                                    if draft.adapterID.supportsKeyParameterMappings {
                                        Text("Key").tag(Optional(LLMParameterEncodingKind.key))
                                    }
                                    if LLMParameterStructuredPreset.allCases.contains(where: {
                                        $0.supports(draft.adapterID)
                                    }) {
                                        Text("Preset").tag(Optional(LLMParameterEncodingKind.preset))
                                    }
                                }
                                if draft.encodingKind == .key {
                                    TextField("Wire key", text: $draft.wireKey)
                                }
                                if draft.encodingKind == .preset {
                                    Picker("Preset", selection: $draft.structuredPreset) {
                                        Text("Select a preset").tag(LLMParameterStructuredPreset?.none)
                                        ForEach(LLMParameterStructuredPreset.allCases.filter {
                                            $0.supports(draft.adapterID)
                                        }) { preset in
                                            Text(preset.displayName).tag(Optional(preset))
                                        }
                                    }
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
                                Picker("Value options", selection: $draft.optionsKind) {
                                    Text("Inherit").tag(ModelDefaultValueOverrideKind.inherit)
                                    Text("Override").tag(ModelDefaultValueOverrideKind.value)
                                    Text("No options").tag(ModelDefaultValueOverrideKind.none)
                                }
                                if draft.optionsKind == .value {
                                    TextField("Comma-separated options", text: $draft.optionsText)
                                }
                            }
                        }
                    } header: {
                        Text("Unsafe Wire Overrides")
                    } footer: {
                        Text("Custom wire keys and presets bypass the adapter contract and are not guaranteed to remain compatible.")
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

    private func parameterSummary(_ profile: LLMParameterProfile?) -> String {
        guard let profile else { return "Unsupported · Fallback" }
        var parts = [profile.support.state.displayName, profile.support.source.displayName]
        if let mapping = profile.mapping, let source = profile.mappingSource {
            parts.append("\(mapping.encodingKind.displayName) · \(source.displayName)")
        }
        if profile.isRequired {
            parts.append("Required")
        }
        return parts.joined(separator: " · ")
    }

    private func capabilityOverrideBinding(_ capability: LLMModelCapability) -> Binding<LLMSupportState?> {
        Binding(
            get: { capabilityOverrides[capability] },
            set: { capabilityOverrides[capability] = $0 }
        )
    }

    private func addParameterOverride(_ parameterID: LLMParameterID) {
        guard !parameterOverrides.contains(where: {
            $0.adapterID == selectedAdapterID && $0.parameterID == parameterID
        }) else { return }
        parameterOverrides.append(ParameterOverrideDraft(ModelParameterOverrideItem(
            adapterID: selectedAdapterID,
            parameterID: parameterID
        )))
    }

    private func overrides(from draft: ParameterOverrideDraft, validateValue: Bool) -> LLMParameterOverrides {
        let mapping: LLMParameterMapping?
        switch draft.encodingKind {
        case .none:
            mapping = nil
        case .key:
            mapping = LLMParameterMapping(
                adapterID: draft.adapterID,
                parameterID: draft.parameterID,
                encodingKind: .key,
                wireKey: draft.wireKey
            )
        case .preset:
            mapping = LLMParameterMapping(
                adapterID: draft.adapterID,
                parameterID: draft.parameterID,
                encodingKind: .preset,
                structuredPreset: draft.structuredPreset
            )
        case .adapter:
            mapping = nil
        }

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

        let options: LLMOptionsOverride
        switch draft.optionsKind {
        case .inherit:
            options = .inherit
        case .none:
            options = .none
        case .value:
            options = .value(draft.optionsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })
        }

        return LLMParameterOverrides(
            support: draft.support,
            mapping: mapping,
            isRequired: draft.required,
            isEnabledByDefault: draft.enabledByDefault,
            defaultValue: defaultValue,
            options: options
        )
    }

    private func save() {
        guard let selectedConfiguration else { return }
        var settings: [(LLMAdapterID, LLMParameterID, LLMParameterOverrides)] = []
        for draft in parameterOverrides {
            let override = overrides(from: draft, validateValue: true)
            guard !showError else { return }
            settings.append((draft.adapterID, draft.parameterID, override))
        }
        do {
            try queryManager.updateModelProfile(
                model,
                modelID: modelID,
                apiConfiguration: selectedConfiguration,
                displayNameOverride: displayNameOverride,
                contextSizeOverride: Int(contextSizeOverride),
                capabilityOverrides: capabilityOverrides,
                parameterOverrides: settings
            )
            dismiss()
        } catch {
            vxAtelierPro.log.error("Failed to save model profile: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
