import Foundation
import SwiftUI
import SwiftData

private struct ModelEditSnapshot {
    let modelID: String
    let displayName: String
    let apiConfiguration: APIConfigurationItem?
    let contextSize: Int
    let capabilitiesRaw: [String]
    let rawMetadataJSON: String?
    let mappingObjects: [ModelParameterMappingItem]
    let mappingSnapshots: [ModelParameterMappingSnapshot]
    let availabilityObjects: [ModelParameterAvailabilityItem]
    let availabilitySnapshots: [ModelParameterAvailabilitySnapshot]

    init(model: ModelItem) {
        modelID = model.modelID
        displayName = model.displayName
        apiConfiguration = model.apiConfiguration
        contextSize = model.contextSize
        capabilitiesRaw = model.capabilitiesRaw
        rawMetadataJSON = model.rawMetadataJSON
        mappingObjects = model.parameterMappings
        mappingSnapshots = model.parameterMappings.map(ModelParameterMappingSnapshot.init)
        availabilityObjects = model.parameterAvailability
        availabilitySnapshots = model.parameterAvailability.map(ModelParameterAvailabilitySnapshot.init)
    }

    func restore(_ model: ModelItem) {
        let originalMappingIDs = Set(mappingObjects.map(ObjectIdentifier.init))
        for mapping in model.parameterMappings where !originalMappingIDs.contains(ObjectIdentifier(mapping)) {
            model.modelContext?.delete(mapping)
        }

        let originalAvailabilityIDs = Set(availabilityObjects.map(ObjectIdentifier.init))
        for availability in model.parameterAvailability where !originalAvailabilityIDs.contains(ObjectIdentifier(availability)) {
            model.modelContext?.delete(availability)
        }

        model.modelID = modelID
        model.displayName = displayName
        model.apiConfiguration = apiConfiguration
        model.contextSize = contextSize
        model.capabilitiesRaw = capabilitiesRaw
        model.rawMetadataJSON = rawMetadataJSON
        model.parameterMappings = mappingObjects
        model.parameterAvailability = availabilityObjects

        for snapshot in mappingSnapshots {
            snapshot.restore()
        }
        for snapshot in availabilitySnapshots {
            snapshot.restore()
        }
    }
}

private struct ModelParameterMappingSnapshot {
    let item: ModelParameterMappingItem
    let adapterIDRaw: String
    let semanticParameterID: String
    let encodingKindRaw: String
    let wireKey: String
    let structuredPresetRaw: String?
    let isCustomized: Bool

    init(_ item: ModelParameterMappingItem) {
        self.item = item
        adapterIDRaw = item.adapterIDRaw
        semanticParameterID = item.semanticParameterID
        encodingKindRaw = item.encodingKindRaw
        wireKey = item.wireKey
        structuredPresetRaw = item.structuredPresetRaw
        isCustomized = item.isCustomized
    }

    func restore() {
        item.adapterIDRaw = adapterIDRaw
        item.semanticParameterID = semanticParameterID
        item.encodingKindRaw = encodingKindRaw
        item.wireKey = wireKey
        item.structuredPresetRaw = structuredPresetRaw
        item.isCustomized = isCustomized
    }
}

private struct ModelParameterAvailabilitySnapshot {
    let item: ModelParameterAvailabilityItem
    let adapterIDRaw: String
    let semanticParameterID: String
    let isAvailable: Bool
    let isRequired: Bool
    let isIncludedByDefault: Bool
    let defaultValueData: Data?
    let isCustomized: Bool

    init(_ item: ModelParameterAvailabilityItem) {
        self.item = item
        adapterIDRaw = item.adapterIDRaw
        semanticParameterID = item.semanticParameterID
        isAvailable = item.isAvailable
        isRequired = item.isRequired
        isIncludedByDefault = item.isIncludedByDefault
        defaultValueData = item.defaultValueData
        isCustomized = item.isCustomized
    }

    func restore() {
        item.adapterIDRaw = adapterIDRaw
        item.semanticParameterID = semanticParameterID
        item.isAvailable = isAvailable
        item.isRequired = isRequired
        item.isIncludedByDefault = isIncludedByDefault
        item.defaultValueData = defaultValueData
        item.isCustomized = isCustomized
    }
}

// MARK: - Model Editor View
struct ModelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]
    
    let model: ModelItem
    @State private var name: String
    @State private var selectedConfigurationID: PersistentIdentifier?
    @State private var contextSize: Int
    @State private var capabilities: [LLMModelCapability]
    @State private var originalSnapshot: ModelEditSnapshot?
    @State private var confirmation: SettingsConfirmation?
    @State private var editorErrorMessage = ""
    @State private var showEditorError = false
    
    init(model: ModelItem) {
        self.model = model
        _name = State(initialValue: model.name)
        _selectedConfigurationID = State(initialValue: model.apiConfiguration?.persistentModelID)
        _contextSize = State(initialValue: model.contextSize)
        _capabilities = State(initialValue: model.capabilities)
        _originalSnapshot = State(initialValue: ModelEditSnapshot(model: model))
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
            ScrollView {
                VStack(spacing: 18) {
                    headerSummary

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            identitySection
                                .frame(maxWidth: .infinity)
                            contextSection
                                .frame(maxWidth: .infinity)
                        }

                        VStack(spacing: 18) {
                            identitySection
                            contextSection
                        }
                    }

                    editorSection(
                        icon: "switch.2",
                        title: "Capabilities",
                        subtitle: "Select the content types and runtime features this model supports."
                    ) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180), spacing: AppDefaults.paddingMedium)],
                            alignment: .leading,
                            spacing: AppDefaults.paddingMedium
                        ) {
                            ForEach(LLMModelCapability.allCases.sorted(by: { $0.displayName < $1.displayName })) { capability in
                                capabilityTile(capability)
                            }
                        }
                        .padding(AppDefaults.paddingLarge)
                    }

                    editorSection(
                        icon: "arrow.left.arrow.right",
                        title: "Parameter Translation",
                        subtitle: "Map semantic controls to adapter-specific request payload fields."
                    ) {
                        sectionActionRow(
                            status: "API Mode: \(selectedAdapterID.displayName)",
                            primaryTitle: "Reset Adapter Defaults",
                            primarySystemImage: "arrow.counterclockwise",
                            primaryAction: {
                                model.resetDefaultParameterMappings(adapterID: selectedAdapterID)
                            },
                            secondaryTitle: "Add Parameter",
                            secondarySystemImage: "plus",
                            secondaryEnabled: !addableParameterIDs.isEmpty,
                            secondaryMenu: {
                                ForEach(addableParameterIDs) { parameterID in
                                    Button(AiParameterPresentationCatalog.displayName(for: parameterID)) {
                                        addMapping(parameterID)
                                    }
                                }
                            }
                        )

                        if selectedAdapterMappings.isEmpty {
                            emptyStateText("No parameters configured for this adapter.")
                        } else {
                            Divider()
                            VStack(spacing: 0) {
                                ForEach(selectedAdapterMappings) { mapping in
                                    ModelParameterMappingRow(mapping: mapping)
                                    if mapping.id != selectedAdapterMappings.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    editorSection(
                        icon: "slider.horizontal.3",
                        title: "Parameter Availability",
                        subtitle: "Declare parameter support, defaults, and required flags for the active adapter."
                    ) {
                        sectionActionRow(
                            status: "API Mode: \(selectedAdapterID.displayName)",
                            primaryTitle: "Reset Availability Defaults",
                            primarySystemImage: "arrow.counterclockwise",
                            primaryAction: {
                                model.resetDefaultParameterAvailability(adapterID: selectedAdapterID)
                            },
                            secondaryTitle: "Add Availability",
                            secondarySystemImage: "plus",
                            secondaryEnabled: !addableAvailabilityParameterIDs.isEmpty,
                            secondaryMenu: {
                                ForEach(addableAvailabilityParameterIDs) { parameterID in
                                    Button(AiParameterPresentationCatalog.displayName(for: parameterID)) {
                                        addAvailability(parameterID)
                                    }
                                }
                            }
                        )

                        if selectedAdapterAvailability.isEmpty {
                            emptyStateText("No parameter availability configured for this adapter.")
                        } else {
                            Divider()
                            VStack(spacing: 0) {
                                ForEach(selectedAdapterAvailability) { availability in
                                    ModelParameterAvailabilityRow(availability: availability)
                                    if availability.id != selectedAdapterAvailability.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    if model.modelContext != nil {
                        editorSection(
                            icon: "exclamationmark.triangle",
                            title: "Danger Zone",
                            subtitle: "Remove this model from the database."
                        ) {
                            HStack {
                                Button(role: .destructive) {
                                    confirmation = SettingsConfirmation(
                                        title: "Delete Model",
                                        message: "Delete \"\(model.name)\"? This action cannot be undone.",
                                        confirmTitle: "Delete",
                                        action: deleteModel
                                    )
                                } label: {
                                    Label("Delete Model", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(AppDefaults.paddingLarge)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle(model.modelContext == nil ? "Add Model" : "Edit Model")
            .toolbar {
                ToolbarItem(placement: .settingsCancel) {
                    Button("Cancel") {
                        originalSnapshot?.restore(model)
                        dismiss()
                    }
                        .font(.system(.body, design: .rounded))
                }
                ToolbarItem(placement: .settingsConfirm) {
                    Button("Save") { save() }
                        .font(.system(.body, design: .rounded))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedConfiguration == nil)
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
            .alert("Model Error", isPresented: $showEditorError) {
                Button("OK") { showEditorError = false }
            } message: {
                Text(editorErrorMessage)
            }
            .settingsConfirmationDialog($confirmation)
        }
    }

    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: AppDefaults.paddingLarge) {
                Image(systemName: "cpu")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.modelContext == nil ? "Add Model" : "Edit Model")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text(name.isEmpty ? "Configure a model profile for conversations and provider requests." : name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: AppDefaults.paddingLarge)

                VStack(alignment: .trailing, spacing: AppDefaults.paddingSmall) {
                    statusPill(
                        selectedConfiguration?.providerIDEnum.displayName ?? "No Provider",
                        systemImage: "network"
                    )
                    statusPill(
                        selectedAdapterID.displayName,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }
            }

            HStack(spacing: AppDefaults.paddingMedium) {
                metricPill(title: "Context", value: formattedTokenCount(contextSize), systemImage: "rectangle.expand.vertical")
                metricPill(title: "Capabilities", value: "\(capabilities.count)", systemImage: "checklist")
                metricPill(title: "Parameters", value: "\(selectedAdapterMappings.count)", systemImage: "arrow.left.arrow.right")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private var identitySection: some View {
        editorSection(
            icon: "person.text.rectangle",
            title: "Model Identity",
            subtitle: "Name and provider configuration used when resolving this model."
        ) {
            editorRow("Model Name") {
                TextField("Model Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            editorDivider()

            editorRow("API Configuration") {
                Picker(selection: $selectedConfigurationID) {
                    ForEach(apiConfigurations) { config in
                        Text(config.name)
                            .tag(config.persistentModelID as PersistentIdentifier?)
                    }
                } label: {
                    Text(selectedConfiguration?.name ?? "Select Configuration")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            editorDivider()

            editorRow("Provider") {
                Text(selectedConfiguration?.providerIDEnum.displayName ?? "No API configuration selected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var contextSection: some View {
        editorSection(
            icon: "rectangle.expand.vertical",
            title: "Context Window",
            subtitle: "Maximum tokens the model can process in a single request."
        ) {
            VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                HStack(alignment: .firstTextBaseline, spacing: AppDefaults.paddingMedium) {
                    TextField("", value: $contextSize, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .monospacedDigit()

                    Text("tokens")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer(minLength: AppDefaults.paddingMedium)

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
                    }
                    .menuStyle(.borderlessButton)
                }

                Text(formattedTokenCount(contextSize))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .padding(AppDefaults.paddingLarge)
        }
    }

    private func editorSection<Content: View>(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
            HStack(alignment: .top, spacing: AppDefaults.paddingMedium) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous)
                            .fill(Color.accentColor.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: 0) {
                content()
            }
            .background(Color.secondary.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous))
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func editorRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent {
                content()
            } label: {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                content()
            }
        }
        .padding(.horizontal, AppDefaults.paddingLarge)
        .padding(.vertical, 10)
    }

    private func editorDivider() -> some View {
        Divider()
            .padding(.leading, AppDefaults.paddingLarge)
    }

    private func sectionActionRow<Content: View>(
        status: String,
        primaryTitle: String,
        primarySystemImage: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondarySystemImage: String,
        secondaryEnabled: Bool,
        @ViewBuilder secondaryMenu: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
            statusPill(status, systemImage: "bolt.horizontal")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppDefaults.paddingMedium) {
                    Button {
                        primaryAction()
                    } label: {
                        Label(primaryTitle, systemImage: primarySystemImage)
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        secondaryMenu()
                    } label: {
                        Label(secondaryTitle, systemImage: secondarySystemImage)
                    }
                    .disabled(!secondaryEnabled)

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Button {
                        primaryAction()
                    } label: {
                        Label(primaryTitle, systemImage: primarySystemImage)
                    }
                    .buttonStyle(.bordered)

                    Menu {
                        secondaryMenu()
                    } label: {
                        Label(secondaryTitle, systemImage: secondarySystemImage)
                    }
                    .disabled(!secondaryEnabled)
                }
            }
        }
        .padding(.horizontal, AppDefaults.paddingLarge)
        .padding(.vertical, AppDefaults.paddingLarge)
    }

    private func emptyStateText(_ text: String) -> some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            Image(systemName: "tray")
                .foregroundColor(.secondary)
            Text(text)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.horizontal, AppDefaults.paddingLarge)
        .padding(.vertical, AppDefaults.paddingLarge)
    }

    private func capabilityTile(_ capability: LLMModelCapability) -> some View {
        let isSelected = capabilities.contains(capability)

        return Button {
            if isSelected {
                capabilities.removeAll { $0 == capability }
            } else {
                capabilities.append(capability)
            }
        } label: {
            HStack(spacing: AppDefaults.paddingMedium) {
                Image(systemName: capability.systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)

                Text(capability.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.6))
            }
            .padding(.horizontal, AppDefaults.paddingMedium)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(capability.displayName)
        .accessibilityValue(isSelected ? "Enabled" : "Disabled")
    }

    private func statusPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.horizontal, AppDefaults.paddingMedium)
            .padding(.vertical, AppDefaults.paddingSmall)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.09))
            )
    }

    private func metricPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: AppDefaults.paddingSmall) {
            Image(systemName: systemImage)
                .foregroundColor(.accentColor)
            Text(title)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, AppDefaults.paddingMedium)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func formattedTokenCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
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
                try queryManager.saveContext()
            }
            dismiss()
        } catch {
            originalSnapshot?.restore(model)
            vxAtelierPro.log.error("Failed to save model \(name): \(error.localizedDescription)")
            editorErrorMessage = "Failed to save model: \(error.localizedDescription)"
            showEditorError = true
        }
    }
    
    private func deleteModel() {
        do {
            try queryManager.delete(model)
            dismiss()
        } catch {
            vxAtelierPro.log.error("Failed to delete model \(model.name): \(error.localizedDescription)")
            editorErrorMessage = "Failed to delete model: \(error.localizedDescription)"
            showEditorError = true
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppDefaults.paddingLarge) {
                Text(mapping.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .frame(width: 150, alignment: .leading)
                    .help(mapping.paramDescription)

                VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
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

                    parameterMappingDetail
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                Text(mapping.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
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

                parameterMappingDetail
            }
        }
        .padding(.horizontal, AppDefaults.paddingLarge)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var parameterMappingDetail: some View {
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
        }
    }
}

private struct ModelParameterAvailabilityRow: View {
    @Bindable var availability: ModelParameterAvailabilityItem

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppDefaults.paddingLarge) {
                Text(availability.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .frame(width: 150, alignment: .leading)
                    .help(availability.paramDescription)

                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    HStack(spacing: AppDefaults.paddingLarge) {
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

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                Text(availability.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .help(availability.paramDescription)

                HStack(spacing: AppDefaults.paddingLarge) {
                    Toggle("Available", isOn: binding(\.isAvailable))
                        .toggleStyle(.switch)

                    Toggle("Required", isOn: binding(\.isRequired))
                        .toggleStyle(.switch)
                }

                Toggle("Included by Default", isOn: binding(\.isIncludedByDefault))
                    .toggleStyle(.switch)

                HStack(spacing: AppDefaults.paddingMedium) {
                    TextField("Default", text: Binding(
                        get: { defaultValueText },
                        set: { defaultValueText = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Text("Leave empty for no model default value.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, AppDefaults.paddingLarge)
        .padding(.vertical, 12)
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
