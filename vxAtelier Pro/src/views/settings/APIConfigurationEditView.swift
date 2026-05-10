import SwiftData
import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// A view for editing or creating an API configuration.
/// Provides a modern interface for managing API connection details with special handling for API keys.
struct APIConfigurationEditView: View {
    // MARK: - Environment & Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]

    let configuration: APIConfigurationItem
    var isNewConfiguration: Bool
    let onSaveCompleted: ((String) -> Void)?

    // MARK: - State

    // Draft form state. Copy into the SwiftData model only when the user saves.
    @State private var name: String
    @State private var apiKey: String
    @State private var baseURL: String
    @State private var isDefault: Bool
    @State private var defaultModel: String
    @State private var providerID: LLMProviderID
    @State private var defaultAdapterID: LLMAdapterID

    // UI state
    @State private var isAPIKeyVisible = false
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""
    @State private var isModelPickerPresented = false
    @State private var hasUserEditedDefaultModel = false
    @State private var isValidating = false
    @State private var isRefreshingModels = false
    @State private var fetchedModelCandidates: [LLMModelDescriptor]?
    @State private var fetchedModelCandidateSignature: String?
    @State private var selectedPreset: APIPreset

    // MARK: - Initialization

    init(
        configuration: APIConfigurationItem,
        isNewConfiguration: Bool = false,
        onSaveCompleted: ((String) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.isNewConfiguration = isNewConfiguration
        self.onSaveCompleted = onSaveCompleted
        _name = State(initialValue: configuration.name)
        _apiKey = State(initialValue: configuration.apiKey)
        _baseURL = State(initialValue: configuration.baseURL)
        _isDefault = State(initialValue: configuration.isDefault)
        _providerID = State(initialValue: configuration.providerIDEnum)
        _defaultAdapterID = State(initialValue: configuration.defaultAdapterIDEnum)
        let initialDefaultModel = (configuration.defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { !$0.isEmpty ? $0 : nil }
            ?? APIConfigurationEditView.suggestedDefaultModel(for: configuration.providerIDEnum)
        _defaultModel = State(initialValue: initialDefaultModel)
        _selectedPreset = State(initialValue: APIPreset.preset(for: configuration.providerIDEnum))
    }

    private var currentProfile: LLMProviderProfile {
        LLMProviderRegistry.shared.profile(for: providerID)
    }

    private var selectableAdapterIDs: [LLMAdapterID] {
        currentProfile.supportedAdapterIDs
    }

    // MARK: - View Body

    var body: some View {
        ScrollView {
            configurationPanel
            .padding(AppDefaults.paddingLarge)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(
            isNewConfiguration ? AppDefaults.newApiConfigurationName : "Edit Configuration"
        )
        .alert("Configuration Error", isPresented: $showValidationError) {
            Button("OK") {
                showValidationError = false
            }
        } message: {
            Text(validationErrorMessage)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isValidating {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isValidating || isRefreshingModels)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    vxAtelierPro.log.debug(
                        "🔑 APIConfigurationListView: Configuration edit cancelled")
                    dismiss()
                }
            }
        }
        .onAppear {
            if !currentProfile.supportedAdapterIDs.contains(defaultAdapterID) {
                defaultAdapterID = currentProfile.defaultAdapterID
            }
        }
        .onChange(of: apiKey) { _, _ in invalidateFetchedModelCandidates() }
        .onChange(of: baseURL) { _, _ in invalidateFetchedModelCandidates() }
        .onChange(of: providerID) { _, _ in invalidateFetchedModelCandidates() }
        .onChange(of: defaultAdapterID) { _, _ in invalidateFetchedModelCandidates() }
    }

    private var configurationPanel: some View {
        VStack(spacing: 0) {
            panelRow("Name") {
                HStack(spacing: AppDefaults.paddingSmall) {
                    TextField("My API Configuration", text: $name)
                        .textFieldStyle(.roundedBorder)

                    defaultButton
                }
            }

            panelDivider()
            panelRow("Provider") {
                Picker("", selection: $selectedPreset) {
                    ForEach(APIPreset.allCases, id: \.self) { preset in
                        Label(preset.displayName, systemImage: preset.iconName)
                            .tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedPreset) { _, _ in
                    applySelectedPreset()
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            panelRow("API URL") {
                TextField("https://api.example.com", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: baseURL) { _, _ in invalidateFetchedModelCandidates() }
            }

            if selectableAdapterIDs.count > 1 {
                panelRow("API Mode") {
                    Picker("", selection: $defaultAdapterID) {
                        ForEach(selectableAdapterIDs) { family in
                            Text(family.displayName).tag(family)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: defaultAdapterID) { _, _ in invalidateFetchedModelCandidates() }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            panelDivider()
            panelRow("API Key", alignment: .top) {
                VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                    HStack(spacing: AppDefaults.paddingSmall) {
                        if isAPIKeyVisible {
                            apiKeyVisibleView
                        } else {
                            SecureField("Enter API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .onChange(of: apiKey) { _, _ in invalidateFetchedModelCandidates() }
                        }

                        Button {
                            isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: isAPIKeyVisible ? "eye.slash.fill" : "eye.fill")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .help(isAPIKeyVisible ? "Hide API key" : "Show API key")

                        if !apiKey.isEmpty {
                            Button {
                                copyToClipboard(apiKey)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy API key")
                        }
                    }
                }
            }

            panelDivider()
            panelRow("Default Model") {
                HStack(spacing: AppDefaults.paddingSmall) {
                    TextField("Default Model", text: $defaultModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: defaultModel) { _, _ in
                            hasUserEditedDefaultModel = true
                        }

                    Button {
                        Task { await loadModelsForPicker() }
                    } label: {
                        if isRefreshingModels {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .frame(width: 22, height: 22)
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Browse provider models")
                }
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .sheet(isPresented: $isModelPickerPresented) {
            ModelSelectionView(
                selectedModel: defaultModel,
                onModelSelected: { model in
                    defaultModel = model
                    hasUserEditedDefaultModel = true
                },
                apiConfiguration: configuration,
                draftModelCandidates: fetchedModelCandidates
            )
        }
    }

    private var defaultButton: some View {
        let isOnlyConfiguration = apiConfigurations.count == 0 || (apiConfigurations.count == 1 && !isNewConfiguration)

        return Button {
            guard !isOnlyConfiguration else {
                validationErrorMessage = "At least one API configuration must be marked as default."
                showValidationError = true
                return
            }
            isDefault.toggle()
        } label: {
            Image(systemName: isDefault ? "star.fill" : "star")
                .foregroundColor(isDefault ? .yellow : .secondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(isDefault ? "Default configuration" : "Set as default")
        .accessibilityLabel(isDefault ? "Default configuration" : "Set as default configuration")
    }

    private func panelRow<Content: View>(
        _ title: String,
        alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: AppDefaults.paddingMedium) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            content()
        }
        .padding(.horizontal, AppDefaults.paddingLarge)
        .padding(.vertical, 7)
    }

    private func panelDivider() -> some View {
        Divider()
    }

    // MARK: - Platform-Specific Views

    @ViewBuilder
    private var apiKeyVisibleView: some View {
        #if os(iOS)
            TextEditor(text: $apiKey)
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .padding(AppDefaults.paddingSmall)
                .background(
                    RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        #else
            TextEditor(text: $apiKey)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 60)
                .padding(AppDefaults.paddingSmall)
                .background(
                    RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        #endif
    }

    /// Suggests a default model for a provider.
    static func suggestedDefaultModel(for providerID: LLMProviderID) -> String {
        LLMModelDescriptorResolver().defaultModelID(for: providerID, apiConfiguration: nil) ?? ""
    }

    // MARK: - Helper Methods

    /// Cross-platform clipboard copy function
    private func copyToClipboard(_ string: String) {
        #if os(iOS)
            UIPasteboard.general.string = string
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #endif
        vxAtelierPro.log.debug("🔑 Copied API key to clipboard")
    }

    private func validateDraft() -> Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationErrorMessage = "Configuration name cannot be empty."
            showValidationError = true
            return false
        }

        return true
    }

    private func validateEndpoint() -> Bool {
        if !baseURL.hasPrefix("http://") && !baseURL.hasPrefix("https://") {
            validationErrorMessage = "Base URL must start with http:// or https://"
            showValidationError = true
            return false
        }

        return true
    }

    /// Saves the configuration changes and refreshes model metadata when possible.
    private func save() async {
        guard validateDraft() else {
            showValidationError = true
            return
        }

        isValidating = true
        defer { isValidating = false }

        do {
            let shouldInsert = isNewConfiguration
            applyDraftToConfiguration()
            try saveConfigurationToStore()
            let refreshSummary = await refreshModelsAfterSave()

            vxAtelierPro.log.info(
                "🔑 Saved configuration and refreshed models: \(configuration.name), isDefault: \(configuration.isDefault), inserted: \(shouldInsert), updated: \(refreshSummary.updated), added: \(refreshSummary.added)"
            )
            if let failure = refreshSummary.failures.first {
                let message = "Saved configuration, but model refresh failed: \(failure.message)"
                onSaveCompleted?(message)
                vxAtelierPro.log.warning(
                    "🔑 Saved configuration \(configuration.name), but model refresh failed: \(failure.message)"
                )
                dismiss()
                return
            }
            dismiss()
        } catch {
            validationErrorMessage = "Failed to save configuration: \(error.localizedDescription)"
            showValidationError = true
            vxAtelierPro.log.error(
                "🔑 Failed to save configuration \(name): \(error.localizedDescription)"
            )
        }
    }

    private func loadModelsForPicker() async {
        guard validateEndpoint() else {
            showValidationError = true
            return
        }

        isRefreshingModels = true
        defer { isRefreshingModels = false }

        do {
            fetchedModelCandidates = try await queryManager.fetchModelCandidates(
                providerID: providerID,
                adapterID: defaultAdapterID,
                configuration: makeProviderConfigurationFromDraft()
            )
            fetchedModelCandidateSignature = draftModelFetchSignature
            isModelPickerPresented = true
        } catch {
            validationErrorMessage = "Failed to fetch models: \(error.localizedDescription)"
            showValidationError = true
            vxAtelierPro.log.error(
                "🔑 Failed to fetch models for configuration \(name): \(error.localizedDescription)"
            )
        }
    }

    private func refreshModelsAfterSave() async -> ModelProviderFetchSummary {
        do {
            let candidates = try await queryManager.fetchModelCandidates(
                providerID: configuration.providerIDEnum,
                adapterID: configuration.defaultAdapterIDEnum,
                configuration: configuration.makeLLMProviderConfiguration()
            )
            return try queryManager.upsertModelCandidates(candidates, for: configuration)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            vxAtelierPro.log.error("🔑 Failed to refresh models after save for \(configuration.name): \(message)")
            if fetchedModelCandidateSignature == draftModelFetchSignature,
               let fetchedModelCandidates,
               !fetchedModelCandidates.isEmpty {
                do {
                    var summary = try queryManager.upsertModelCandidates(fetchedModelCandidates, for: configuration)
                    summary.failures.append(ModelProviderFetchFailure(
                        configurationName: configuration.name,
                        providerID: configuration.providerIDEnum,
                        message: message
                    ))
                    return summary
                } catch {
                    return ModelProviderFetchSummary(failures: [
                        ModelProviderFetchFailure(
                            configurationName: configuration.name,
                            providerID: configuration.providerIDEnum,
                            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        )
                    ])
                }
            }
            return ModelProviderFetchSummary(failures: [
                ModelProviderFetchFailure(
                    configurationName: configuration.name,
                    providerID: configuration.providerIDEnum,
                    message: message
                )
            ])
        }
    }

    private var draftModelFetchSignature: String {
        [
            providerID.rawValue,
            defaultAdapterID.rawValue,
            baseURL,
            apiKey,
            configuration.headersJSON,
            configuration.optionsJSON
        ].joined(separator: "\u{1F}")
    }

    private func invalidateFetchedModelCandidates() {
        guard fetchedModelCandidateSignature != draftModelFetchSignature else { return }
        fetchedModelCandidates = nil
        fetchedModelCandidateSignature = nil
    }

    private func makeProviderConfigurationFromDraft() -> LLMProviderConfiguration {
        return APIConfigurationItem.makeLLMProviderConfiguration(
            providerID: providerID,
            authKind: currentProfile.authKind,
            apiKey: apiKey,
            baseURL: baseURL,
            headers: configuration.decodedHeaders,
            options: configuration.decodedOptions
        )
    }

    private func applyDraftToConfiguration() {
        configuration.name = name
        configuration.apiKey = apiKey
        configuration.baseURL = baseURL
        let profile = LLMProviderRegistry.shared.profile(for: providerID)
        configuration.providerID = providerID.rawValue
        configuration.authKind = profile.authKind.rawValue
        configuration.defaultAdapterID = defaultAdapterID.rawValue

        let configsCount = apiConfigurations.count
        if configsCount == 0 || configsCount == 1 && !isNewConfiguration {
            isDefault = true
        }
        configuration.isDefault = isDefault

        let trimmedDefaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDefaultModel.isEmpty {
            let suggested = APIConfigurationEditView.suggestedDefaultModel(for: providerID)
            configuration.defaultModel = suggested
            vxAtelierPro.log.info("🔑 Set default model to computed default: \(suggested)")
        } else {
            configuration.defaultModel = trimmedDefaultModel
        }
    }

    private func saveConfigurationToStore() throws {
        try queryManager.upsertAPIConfiguration(configuration, makeDefault: isDefault)
    }

    /// Applies the selected preset to the configuration
    private func applySelectedPreset() {
        let preset = selectedPreset

        let allow_new_name_for =
            APIPreset.allCases.map { $0.displayName } + [AppDefaults.newApiConfigurationName, ""]

        if allow_new_name_for.contains(name) {
            name = preset.displayName
        }

        baseURL = preset.baseURL
        providerID = preset.providerID
        defaultAdapterID = LLMProviderRegistry.shared.profile(for: preset.providerID).defaultAdapterID

        defaultModel = APIConfigurationEditView.suggestedDefaultModel(for: preset.providerID)
        hasUserEditedDefaultModel = false

        vxAtelierPro.log.info("🔑 Applied \(preset.displayName) preset")
    }
}

// MARK: - API Presets

/// Predefined configurations for common API providers
enum APIPreset: String, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case xAI = "xAI"
    case deepSeek = "DeepSeek"
    case openRouter = "OpenRouter"
    case lmStudio = "LM Studio"
    case ollama = "Ollama"
    case customOpenAICompatible = "Custom"

    var displayName: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .openAI: return "sparkles"
        case .anthropic: return "person.text.rectangle"
        case .xAI: return "bolt.fill"
        case .deepSeek: return "brain"
        case .openRouter: return "point.3.connected.trianglepath.dotted"
        case .lmStudio: return "desktopcomputer"
        case .ollama: return "terminal"
        case .customOpenAICompatible: return "slider.horizontal.3"
        }
    }

    var providerID: LLMProviderID {
        switch self {
        case .openAI: return .openAIPlatform
        case .anthropic: return .anthropic
        case .xAI: return .xAI
        case .deepSeek: return .deepSeek
        case .openRouter: return .openRouter
        case .lmStudio: return .lmStudio
        case .ollama: return .ollama
        case .customOpenAICompatible: return .customOpenAICompatible
        }
    }

    static func preset(for providerID: LLMProviderID) -> APIPreset {
        switch providerID {
        case .openAIPlatform:
            return .openAI
        case .anthropic:
            return .anthropic
        case .xAI:
            return .xAI
        case .deepSeek:
            return .deepSeek
        case .openRouter:
            return .openRouter
        case .lmStudio:
            return .lmStudio
        case .ollama:
            return .ollama
        case .customOpenAICompatible:
            return .customOpenAICompatible
        case .openAIChatGPTSubscription:
            return .openAI
        }
    }

    var baseURL: String {
        switch self {
        case .openAI: return AppDefaults.OpenAi.baseURL
        case .anthropic: return AppDefaults.Anthropic.baseURL
        case .xAI: return AppDefaults.XAI.baseURL
        case .deepSeek: return AppDefaults.DeepSeek.baseURL
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .lmStudio: return "http://localhost:1234/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .customOpenAICompatible: return AppDefaults.OpenAi.baseURL
        }
    }

}

// MARK: - Validation Error
private struct ValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
