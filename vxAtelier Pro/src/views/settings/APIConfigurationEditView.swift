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

    @Bindable var configuration: APIConfigurationItem
    var isNewConfiguration: Bool

    // MARK: - State

    // Local state to avoid constant model updates
    @State private var name: String
    @State private var apiKey: String
    @State private var baseURL: String
    @State private var chatEndpoint: String
    @State private var modelsEndpoint: String
    @State private var isDefault: Bool
    @State private var defaultModel: String

    // UI state
    @State private var isAPIKeyVisible = false
    @State private var selectedPreset: APIPreset?
    @State private var showPresetConfirmation = false
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""
    @State private var isModelPickerPresented = false
    @State private var hasUserEditedDefaultModel = false
    @State private var isValidating = false

    // MARK: - Initialization

    init(configuration: APIConfigurationItem, isNewConfiguration: Bool = false) {
        self.configuration = configuration
        self.isNewConfiguration = isNewConfiguration
        _name = State(initialValue: configuration.name)
        _apiKey = State(initialValue: configuration.apiKey)
        _baseURL = State(initialValue: configuration.baseURL)
        _chatEndpoint = State(initialValue: configuration.chatCompletionsEndpoint)
        _modelsEndpoint = State(initialValue: configuration.modelsEndpoint)
        _isDefault = State(initialValue: configuration.isDefault)
        let initialDefaultModel = (configuration.defaultModel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { !$0.isEmpty ? $0 : nil }
            ?? APIConfigurationEditView.suggestedDefaultModel(for: configuration.baseURL)
        _defaultModel = State(initialValue: initialDefaultModel)
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
                                    isModelPickerPresented = true
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
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
                                    currentProvider: AIServiceProvider.detectProvider(
                                        from: configuration)
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
                                        applyPreset()
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
                        // Base URL
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Base URL")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("https://api.example.com", text: $baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        // Chat Endpoint
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Chat Completions Endpoint")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("/v1/chat/completions", text: $chatEndpoint)
                                .textFieldStyle(.roundedBorder)
                        }
                        // Models Endpoint
                        VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                            Text("Models Endpoint")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("/v1/models", text: $modelsEndpoint)
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
        .alert("Validation Error", isPresented: $showValidationError) {
            Button("OK") {
                showValidationError = false
            }
        } message: {
            Text(validationErrorMessage)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveConfigurationAsync() }
                } label: {
                    if isValidating {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isValidating)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    vxAtelierPro.log.debug(
                        "🔑 APIConfigurationListView: Configuration edit cancelled")
                    dismiss()
                }
            }
        }
        .onChange(of: baseURL) { _, newValue in
            if !hasUserEditedDefaultModel || defaultModel.isEmpty {
                defaultModel = APIConfigurationEditView.suggestedDefaultModel(for: newValue)
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

    /// Suggests a default model for a given baseURL/provider
    static func suggestedDefaultModel(for baseURL: String) -> String {
        let provider = AIServiceProvider.detectProvider(from: baseURL)
        switch provider {
        case .openAI: return AppDefaults.OpenAi.model
        case .anthropic: return AppDefaults.Anthropic.model
        case .xAI: return AppDefaults.XAI.model
        case .deepSeek: return AppDefaults.DeepSeek.model
        }
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

    /// Performs a lightweight validation against the provider (fetch models)
    private func validateConfiguration(_ config: APIConfigurationItem) async throws {
        let service = AIServiceManager.shared.getService(with: config)
        _ = try await service.fetchAvailableModels()
    }

    /// Validates all input fields before saving
    /// - Returns: True if all inputs are valid
    private func validateInputs() -> Bool {
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

    /// Saves the configuration changes with validation against the provider
    private func saveConfigurationAsync() async {
        guard validateInputs() else {
            showValidationError = true
            return
        }

        isValidating = true
        defer { isValidating = false }

        let configToSave = configuration
        let shouldInsert = isNewConfiguration

        configToSave.name = name
        configToSave.apiKey = apiKey
        configToSave.baseURL = baseURL
        configToSave.chatCompletionsEndpoint = chatEndpoint
        configToSave.modelsEndpoint = modelsEndpoint

        let configsCount = apiConfigurations.count
        if configsCount == 0 {
            isDefault = true
        } else if configsCount == 1 && !isNewConfiguration {
            isDefault = true
        }

        configToSave.isDefault = isDefault
        if configToSave.isDefault {
            for other in apiConfigurations
            where other.id != configToSave.id && other.isDefault {
                other.isDefault = false
                vxAtelierPro.log.debug("🔑 Unset previous default: \(other.name)")
            }
        }

        let trimmedDefaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDefaultModel.isEmpty {
            let suggested = APIConfigurationEditView.suggestedDefaultModel(for: baseURL)
            configToSave.defaultModel = suggested
            vxAtelierPro.log.info("🔑 Set default model to computed default: \(suggested)")
        } else {
            configToSave.defaultModel = trimmedDefaultModel
        }

        do {
            try await validateConfiguration(configToSave)
        } catch {
            validationErrorMessage = "Failed to validate configuration: \(error.localizedDescription)"
            showValidationError = true
            vxAtelierPro.log.error(
                "🔑 Validation failed for configuration \(configToSave.name): \(error.localizedDescription)"
            )
            return
        }

        do {
            if shouldInsert {
                try queryManager.insert(configToSave)
                vxAtelierPro.log.info(
                    "🔑 Inserted configuration: \(configToSave.name), isDefault: \(configToSave.isDefault)"
                )
            } else {
                try queryManager.saveContext()
            }
            dismiss()
        } catch {
            validationErrorMessage = "Failed to save configuration: \(error.localizedDescription)"
            showValidationError = true
            vxAtelierPro.log.error(
                "🔑 Failed to save configuration \(configToSave.name): \(error.localizedDescription)"
            )
        }
    }

    /// Applies the selected preset to the configuration
    private func applyPreset() {
        guard let preset = selectedPreset else { return }

        let allow_new_name_for =
            APIPreset.allCases.map { $0.displayName } + [AppDefaults.newApiConfigurationName, ""]

        if allow_new_name_for.contains(name) {
            name = preset.displayName
        }

        baseURL = preset.baseURL
        chatEndpoint = preset.chatEndpoint
        modelsEndpoint = preset.modelsEndpoint

        // Always set the default model to the computed default for the selected provider
        defaultModel = APIConfigurationEditView.suggestedDefaultModel(for: preset.baseURL)
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

    var displayName: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .openAI: return "sparkles"
        case .anthropic: return "person.text.rectangle"
        case .xAI: return "bolt.fill"
        case .deepSeek: return "brain"
        }
    }

    var color: Color {
        switch self {
        case .openAI: return .green
        case .anthropic: return .purple
        case .xAI: return .red
        case .deepSeek: return .blue
        }
    }

    var baseURL: String {
        switch self {
        case .openAI: return AppDefaults.OpenAi.baseURL
        case .anthropic: return AppDefaults.Anthropic.baseURL
        case .xAI: return AppDefaults.XAI.baseURL
        case .deepSeek: return AppDefaults.DeepSeek.baseURL
        }
    }

    var chatEndpoint: String {
        switch self {
        case .openAI: return AppDefaults.OpenAi.chatCompletionsEndpoint
        case .anthropic: return AppDefaults.Anthropic.chatCompletionsEndpoint
        case .xAI: return AppDefaults.XAI.chatCompletionsEndpoint
        case .deepSeek: return AppDefaults.DeepSeek.chatCompletionsEndpoint
        }
    }

    var modelsEndpoint: String {
        switch self {
        case .openAI: return AppDefaults.OpenAi.modelsEndpoint
        case .anthropic: return AppDefaults.Anthropic.modelsEndpoint
        case .xAI: return AppDefaults.XAI.modelsEndpoint
        case .deepSeek: return AppDefaults.DeepSeek.modelsEndpoint
        }
    }
}

// MARK: - Validation Error
private struct ValidationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
