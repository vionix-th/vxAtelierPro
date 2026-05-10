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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]

    let configuration: APIConfigurationItem
    var isNewConfiguration: Bool

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
    @State private var selectedPreset: APIPreset?
    @State private var showPresetConfirmation = false
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""
    @State private var isModelPickerPresented = false
    @State private var hasUserEditedDefaultModel = false
    @State private var isValidating = false
    @State private var isRefreshingModels = false
    @State private var fetchedModelDescriptors: [LLMModelDescriptor]?

    // MARK: - Initialization

    init(configuration: APIConfigurationItem, isNewConfiguration: Bool = false) {
        self.configuration = configuration
        self.isNewConfiguration = isNewConfiguration
        _name = State(initialValue: configuration.name)
        _apiKey = State(initialValue: configuration.apiKey)
        _baseURL = State(initialValue: configuration.baseURL)
        _isDefault = State(initialValue: configuration.isDefault)
        _providerID = State(initialValue: configuration.providerIDEnum)
        _defaultAdapterID = State(initialValue: configuration.defaultAdapterIDEnum)
        let initialDefaultModel = (configuration.defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { !$0.isEmpty ? $0 : nil }
            ?? APIConfigurationEditView.suggestedDefaultModel(for: configuration.providerIDEnum)
        _defaultModel = State(initialValue: initialDefaultModel)
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
            VStack(spacing: AppDefaults.paddingLarge) {
                // Name and Preset Section
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Basic Information")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppDefaults.paddingLarge)

                    VStack(spacing: AppDefaults.paddingMedium) {
                        // Name Field
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Configuration Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            TextField("My API Configuration", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal, AppDefaults.paddingSmall)
                        }
                        // Default Configuration Toggle
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            let configsCount = apiConfigurations.count
                            let toggleDisabled: Bool = {
                                if configsCount == 0 { return true } // first config must stay default
                                if configsCount == 1 && !isNewConfiguration { return true } // only config cannot be unset
                                return false
                            }()

                            Toggle(isOn: $isDefault) {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text("Use as Default Configuration")
                                        .foregroundColor(.primary)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.horizontal, AppDefaults.paddingSmall)
                            .disabled(toggleDisabled)
                            .help(toggleDisabled ? "The only configuration must remain default." : "")
                            if toggleDisabled {
                                Text("The only configuration must remain default.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        // Default Model Selector
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Default Model")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack {
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
                                            .frame(width: 20, height: 20)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .disabled(isValidating || isRefreshingModels)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(AppDefaults.cornerRadiusSmall)
                            .sheet(isPresented: $isModelPickerPresented) {
                                ModelSelectionView(
                                    selectedModel: defaultModel,
                                    onModelSelected: { model in
                                        defaultModel = model
                                        hasUserEditedDefaultModel = true
                                    },
                                    apiConfiguration: configuration,
                                    fallbackModels: nil,
                                    fallbackModelDescriptors: fetchedModelDescriptors
                                )
                            }
                            Text(
                                "This model will be used by default for new conversations using this configuration."
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(AppDefaults.paddingLarge)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
                    .padding(.horizontal, AppDefaults.paddingLarge)
                }

                // API Key Section
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Authentication")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppDefaults.paddingLarge)

                    VStack(spacing: AppDefaults.paddingMedium) {
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("API Key")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack {
                                if isAPIKeyVisible {
                                    apiKeyVisibleView
                                } else {
                                    SecureField("Enter API Key", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }

                                Button {
                                    isAPIKeyVisible.toggle()
                                } label: {
                                    Image(
                                        systemName: isAPIKeyVisible ? "eye.slash.fill" : "eye.fill"
                                    )
                                    .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            if !apiKey.isEmpty {
                                HStack {
                                    Text("Key length: \(apiKey.count) characters")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Button {
                                        copyToClipboard(apiKey)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .padding(AppDefaults.paddingLarge)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
                    .padding(.horizontal, AppDefaults.paddingLarge)
                }

                // Endpoint Configuration Section
                VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                    Text("Endpoint Configuration")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppDefaults.paddingLarge)

                    VStack(spacing: AppDefaults.paddingMedium) {
                        // Presets Selector (moved here)
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Presets")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            LazyVGrid(
                                columns: [
                                    GridItem(
                                        .adaptive(minimum: 100), spacing: AppDefaults.paddingSmall)
                                ], spacing: AppDefaults.paddingSmall
                            ) {
                                ForEach(APIPreset.allCases, id: \.self) { preset in
                                    Button {
                                        selectedPreset = preset
                                        applySelectedPreset()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: preset.iconName)
                                                .foregroundColor(preset.color)
                                                .font(.caption)
                                            Text(preset.displayName)
                                                .font(.caption)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(
                                                cornerRadius: AppDefaults.cornerRadiusSmall
                                            )
                                            .fill(preset.color.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(
                                                    cornerRadius: AppDefaults.cornerRadiusSmall
                                                )
                                                .stroke(preset.color.opacity(0.3), lineWidth: 1)
                                            )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, AppDefaults.paddingSmall)
                        }
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Default API Mode")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if selectableAdapterIDs.count > 1 {
                                Picker("", selection: $defaultAdapterID) {
                                    ForEach(selectableAdapterIDs) { family in
                                        Text(family.displayName).tag(family)
                                    }
                                }
                                .pickerStyle(.segmented)
                            } else {
                                Text(selectableAdapterIDs.first?.displayName ?? currentProfile.defaultAdapterID.displayName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundColor(.secondary)
                            }
                        }
                        // Base URL
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Base URL")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("https://api.example.com", text: $baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(AppDefaults.paddingLarge)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
                    .padding(.horizontal, AppDefaults.paddingLarge)
                }
            }
            .padding(.vertical, AppDefaults.paddingLarge)
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
        .onChange(of: providerID) { _, newValue in
            if !hasUserEditedDefaultModel || defaultModel.isEmpty {
                defaultModel = APIConfigurationEditView.suggestedDefaultModel(for: newValue)
            }
            fetchedModelDescriptors = nil
            let profile = LLMProviderRegistry.shared.profile(for: newValue)
            if !profile.supportedAdapterIDs.contains(defaultAdapterID) {
                defaultAdapterID = profile.defaultAdapterID
            }
        }
        .onAppear {
            if !currentProfile.supportedAdapterIDs.contains(defaultAdapterID) {
                defaultAdapterID = currentProfile.defaultAdapterID
            }
        }
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

    /// Validates all input fields before saving
    /// - Returns: True if all inputs are valid
    private func validateDraft() -> Bool {
        // Check for empty name
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationErrorMessage = "Configuration name cannot be empty."
            showValidationError = true
            return false
        }

        // Check for valid base URL
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
            let refreshSummary = await queryManager.refreshModels(for: configuration)

            vxAtelierPro.log.info(
                "🔑 Saved configuration and refreshed models: \(configuration.name), isDefault: \(configuration.isDefault), inserted: \(shouldInsert), updated: \(refreshSummary.updated), added: \(refreshSummary.added)"
            )
            if let failure = refreshSummary.failures.first {
                validationErrorMessage = "Saved configuration, but model refresh failed: \(failure.message)"
                showValidationError = true
                vxAtelierPro.log.warning(
                    "🔑 Saved configuration \(configuration.name), but model refresh failed: \(failure.message)"
                )
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
        guard validateDraft() else {
            showValidationError = true
            return
        }

        isRefreshingModels = true
        defer { isRefreshingModels = false }

        do {
            fetchedModelDescriptors = try await queryManager.fetchModelDescriptors(
                providerID: providerID,
                adapterID: defaultAdapterID,
                configuration: makeProviderConfigurationFromDraft()
            )
            isModelPickerPresented = true
        } catch {
            validationErrorMessage = "Failed to fetch models: \(error.localizedDescription)"
            showValidationError = true
            vxAtelierPro.log.error(
                "🔑 Failed to fetch models for configuration \(name): \(error.localizedDescription)"
            )
        }
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
        guard let preset = selectedPreset else { return }

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
        selectedPreset = nil
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

    var color: Color {
        switch self {
        case .openAI: return .green
        case .anthropic: return .purple
        case .xAI: return .red
        case .deepSeek: return .blue
        case .openRouter: return .orange
        case .lmStudio: return .teal
        case .ollama: return .gray
        case .customOpenAICompatible: return .secondary
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
