import SwiftData
import SwiftUI

/// Rollback snapshot for API configuration edits.
private struct APIConfigurationEditSnapshot {
    let name: String
    let apiKey: String
    let baseURL: String
    let isDefault: Bool
    let providerID: String
    let authKind: String
    let defaultAdapterID: String
    let defaultModel: String?
    let credentialJSON: String

    init(_ configuration: APIConfigurationItem) {
        name = configuration.name
        apiKey = configuration.apiKey
        baseURL = configuration.baseURL
        isDefault = configuration.isDefault
        providerID = configuration.providerID
        authKind = configuration.authKind
        defaultAdapterID = configuration.defaultAdapterID
        defaultModel = configuration.defaultModel
        credentialJSON = configuration.credentialJSON
    }

    func restore(_ configuration: APIConfigurationItem) {
        configuration.name = name
        configuration.apiKey = apiKey
        configuration.baseURL = baseURL
        configuration.isDefault = isDefault
        configuration.providerID = providerID
        configuration.authKind = authKind
        configuration.defaultAdapterID = defaultAdapterID
        configuration.defaultModel = defaultModel
        configuration.credentialJSON = credentialJSON
    }
}

/// Editor for API provider configuration records.
struct APIConfigurationEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(QueryManager.self) private var queryManager
    @Query(sort: [SortDescriptor(\APIConfigurationItem.name)]) private var apiConfigurations: [APIConfigurationItem]

    let configuration: APIConfigurationItem
    var isNewConfiguration: Bool
    let onSaveCompleted: ((String) -> Void)?

    @State private var name: String
    @State private var apiKey: String
    @State private var baseURL: String
    @State private var isDefault: Bool
    @State private var defaultModel: String
    @State private var providerID: LLMProviderID
    @State private var defaultAdapterID: LLMAdapterID
    @State private var isAPIKeyVisible = false
    @State private var showValidationError = false
    @State private var validationErrorMessage = ""
    @State private var isModelPickerPresented = false
    @State private var isValidating = false
    @State private var isRefreshingModels = false
    @State private var fetchedModelCandidates: [LLMModelDescriptor]?
    @State private var fetchedModelCandidateSignature: String?
    @State private var selectedPreset: APIPreset
    @State private var isCodexAuthenticating = false
    @State private var codexAuthStatusMessage: String?
    @State private var deviceCodeChallenge: CodexChatGPTOAuthService.DeviceCodeChallenge?
    @State private var codexCredentialJSON: String

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
        _codexCredentialJSON = State(initialValue: configuration.credentialJSON)
    }

    private var currentProfile: LLMProviderProfile {
        LLMProviderRegistry.shared.profile(for: providerID)
    }

    private var selectableAdapterIDs: [LLMAdapterID] {
        currentProfile.supportedAdapterIDs
    }

    var body: some View {
        SettingsPage(title: isNewConfiguration ? AppDefaults.newApiConfigurationName : "Edit Configuration") {
            SettingsFormSection("Connection") {
                LabeledContent("Name") {
                    HStack(spacing: AppDefaults.paddingSmall) {
                        TextField("", text: $name)
                            .textFieldStyle(.roundedBorder)

                        defaultButton
                    }
                }

                SettingsPickerRow("Provider", selection: $selectedPreset) {
                    ForEach(APIPreset.allCases, id: \.self) { preset in
                        Label(preset.displayName, systemImage: preset.iconName)
                            .tag(preset)
                    }
                }
                .onChange(of: selectedPreset) { _, _ in
                    applySelectedPreset()
                }

                if currentProfile.requiresBaseURL {
                    LabeledContent("API URL") {
                        TextField("", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: baseURL) { _, _ in invalidateFetchedModelCandidates() }
                    }
                }

                if selectableAdapterIDs.count > 1 {
                    SettingsPickerRow("API Mode", selection: $defaultAdapterID) {
                        ForEach(selectableAdapterIDs) { family in
                            Text(family.displayName).tag(family)
                        }
                    }
                    .onChange(of: defaultAdapterID) { _, _ in invalidateFetchedModelCandidates() }
                }
            }

            SettingsFormSection("Credentials") {
                if currentProfile.transportKind == .localSystem {
                    LabeledContent("Status") {
                        Text(localProviderStatusText)
                            .foregroundStyle(.secondary)
                    }
                } else if isCodexChatGPTSubscription {
                    codexChatGPTAuthControls
                } else if currentProfile.requiresCredential {
                    LabeledContent("API Key") {
                        HStack(spacing: AppDefaults.paddingSmall) {
                            apiKeyField

                            Button {
                                isAPIKeyVisible.toggle()
                            } label: {
                                Image(systemName: isAPIKeyVisible ? "eye.slash.fill" : "eye.fill")
                            }
                            .buttonStyle(.borderless)
                            .help(isAPIKeyVisible ? "Hide API key" : "Show API key")

                            if !apiKey.isEmpty {
                                Button {
                                    ExportUtils.copyToClipboard(apiKey)
                                    vxAtelierPro.log.debug("Copied API key to clipboard")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .help("Copy API key")
                            }
                        }
                    }
                }
            }

            SettingsFormSection("Model Defaults") {
                LabeledContent("Default Model") {
                    HStack(spacing: AppDefaults.paddingSmall) {
                        TextField("", text: $defaultModel)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: defaultModel) { _, _ in
                                invalidateFetchedModelCandidates()
                            }

                        Button {
                            Task { await loadModelsForPicker() }
                        } label: {
                            if isRefreshingModels {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .buttonStyle(.borderless)
                        .help("Browse provider models")
                    }
                }
            }
        }
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
                    vxAtelierPro.log.debug("API configuration edit cancelled")
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
        .sheet(isPresented: $isModelPickerPresented) {
            ModelSelectionView(
                selectedModel: defaultModel,
                onModelSelected: { model in
                    defaultModel = model
                    invalidateFetchedModelCandidates()
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
        }
        .buttonStyle(.borderless)
        .help(isDefault ? "Default configuration" : "Set as default")
        .accessibilityLabel(isDefault ? "Default configuration" : "Set as default configuration")
    }

    private var isCodexChatGPTSubscription: Bool {
        providerID == .openAICodexChatGPTSubscription
    }

    private var codexTokenSet: CodexChatGPTTokenSet? {
        CodexChatGPTTokenSet.decoded(from: codexCredentialJSON)?.withClaimsFromTokens()
    }

    @ViewBuilder
    private var codexChatGPTAuthControls: some View {
        LabeledContent("Status") {
            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                Text(codexAuthStatusText)
                    .foregroundStyle(codexTokenSet == nil ? .secondary : .primary)
                if let message = codexAuthStatusMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }

        if let challenge = deviceCodeChallenge {
            LabeledContent("Device Code") {
                HStack(spacing: AppDefaults.paddingSmall) {
                    Text(challenge.userCode)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        ExportUtils.copyToClipboard(challenge.userCode)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy device code")
                    Button {
                        openURL(challenge.verificationURL)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.borderless)
                    .help("Open verification page")
                }
            }
        }

        LabeledContent("Sign In") {
            HStack(spacing: AppDefaults.paddingSmall) {
                Button {
                    signInWithCodexBrowser()
                } label: {
                    Label("Browser", systemImage: "safari")
                }
                .disabled(isCodexAuthenticating)

                Button {
                    signInWithCodexDeviceCode()
                } label: {
                    Label("Device Code", systemImage: "rectangle.connected.to.line.below")
                }
                .disabled(isCodexAuthenticating)

                if isCodexAuthenticating {
                    ProgressView()
                }
            }
        }

        if codexTokenSet != nil {
            LabeledContent("Token") {
                HStack(spacing: AppDefaults.paddingSmall) {
                    Button {
                        refreshCodexToken()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isCodexAuthenticating)

                    Button(role: .destructive) {
                        signOutCodex()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(isCodexAuthenticating)
                }
            }
        }
    }

    private var codexAuthStatusText: String {
        guard let tokenSet = codexTokenSet else {
            return "Not signed in to Codex ChatGPT Subscription."
        }
        let identity = tokenSet.email ?? tokenSet.accountID ?? "signed-in account"
        return "Signed in as \(identity)."
    }

    @ViewBuilder
    private var apiKeyField: some View {
        if isAPIKeyVisible {
            TextEditor(text: $apiKey)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70)
                .onChange(of: apiKey) { _, _ in invalidateFetchedModelCandidates() }
        } else {
            SecureField("", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: apiKey) { _, _ in invalidateFetchedModelCandidates() }
        }
    }

    static func suggestedDefaultModel(for providerID: LLMProviderID) -> String {
        LLMModelDescriptorResolver().defaultModelID(for: providerID, apiConfiguration: nil) ?? ""
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
        guard currentProfile.requiresBaseURL else { return true }
        if !baseURL.hasPrefix("http://") && !baseURL.hasPrefix("https://") {
            validationErrorMessage = "Base URL must start with http:// or https://"
            showValidationError = true
            return false
        }

        return true
    }

    private func save() async {
        guard validateDraft() else {
            showValidationError = true
            return
        }

        isValidating = true
        defer { isValidating = false }

        do {
            let shouldInsert = isNewConfiguration
            let snapshot = APIConfigurationEditSnapshot(configuration)
            applyDraftToConfiguration()
            do {
                try saveConfigurationToStore()
            } catch {
                snapshot.restore(configuration)
                throw error
            }
            let refreshSummary = await refreshModelsAfterSave()

            vxAtelierPro.log.info(
                "Saved configuration and refreshed models: \(configuration.name), isDefault: \(configuration.isDefault), inserted: \(shouldInsert), updated: \(refreshSummary.updated), added: \(refreshSummary.added)"
            )
            if let failure = refreshSummary.failures.first {
                let message = "Saved configuration, but model refresh failed: \(failure.message)"
                onSaveCompleted?(message)
                vxAtelierPro.log.warning(
                    "Saved configuration \(configuration.name), but model refresh failed: \(failure.message)"
                )
                dismiss()
                return
            }
            dismiss()
        } catch {
            validationErrorMessage = "Failed to save configuration: \(error.localizedDescription)"
            showValidationError = true
            vxAtelierPro.log.error(
                "Failed to save configuration \(name): \(error.localizedDescription)"
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
                "Failed to fetch models for configuration \(name): \(error.localizedDescription)"
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
            vxAtelierPro.log.error("Failed to refresh models after save for \(configuration.name): \(message)")
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
            codexCredentialJSON,
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
        if providerID == .openAICodexChatGPTSubscription {
            var headers = configuration.decodedHeaders
            let tokenSet = codexTokenSet
            if let accountID = tokenSet?.accountID, !accountID.isEmpty {
                headers["ChatGPT-Account-Id"] = accountID
            }
            headers["originator"] = headers["originator"] ?? "vxatelier_pro"
            return APIConfigurationItem.makeLLMProviderConfiguration(
                providerID: providerID,
                authKind: tokenSet?.authMethod ?? .codexChatGPTOAuth,
                apiKey: tokenSet?.accessToken ?? "",
                baseURL: baseURL,
                headers: headers,
                options: configuration.decodedOptions
            )
        }
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
        if providerID == .openAICodexChatGPTSubscription {
            configuration.authKind = (codexTokenSet?.authMethod ?? .codexChatGPTOAuth).rawValue
            configuration.apiKey = ""
            configuration.credentialJSON = codexCredentialJSON
        } else if profile.requiresCredential {
            configuration.credentialJSON = "{}"
        } else {
            configuration.apiKey = ""
            configuration.baseURL = ""
            configuration.credentialJSON = "{}"
        }

        let configsCount = apiConfigurations.count
        if configsCount == 0 || configsCount == 1 && !isNewConfiguration {
            isDefault = true
        }
        configuration.isDefault = isDefault

        let trimmedDefaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDefaultModel.isEmpty {
            let suggested = APIConfigurationEditView.suggestedDefaultModel(for: providerID)
            configuration.defaultModel = suggested
            vxAtelierPro.log.info("Set default model to computed default: \(suggested)")
        } else {
            configuration.defaultModel = trimmedDefaultModel
        }
    }

    private func saveConfigurationToStore() throws {
        try queryManager.upsertAPIConfiguration(configuration, makeDefault: isDefault)
    }

    private func applySelectedPreset() {
        let preset = selectedPreset

        let defaultNames =
            APIPreset.allCases.map { $0.displayName } + [AppDefaults.newApiConfigurationName, ""]

        if defaultNames.contains(name) {
            name = preset.displayName
        }

        baseURL = preset.baseURL
        providerID = preset.providerID
        defaultAdapterID = LLMProviderRegistry.shared.profile(for: preset.providerID).defaultAdapterID
        if preset.providerID == .openAICodexChatGPTSubscription {
            apiKey = ""
        } else if !LLMProviderRegistry.shared.profile(for: preset.providerID).requiresCredential {
            apiKey = ""
        }
        if !LLMProviderRegistry.shared.profile(for: preset.providerID).requiresBaseURL {
            baseURL = ""
        }

        defaultModel = APIConfigurationEditView.suggestedDefaultModel(for: preset.providerID)

        vxAtelierPro.log.info("Applied \(preset.displayName) preset")
    }

    private func applyCodexToken(_ tokenSet: CodexChatGPTTokenSet) {
        providerID = .openAICodexChatGPTSubscription
        selectedPreset = .codexChatGPTSubscription
        baseURL = CodexChatGPTOAuthService.codexBackendBaseURL
        defaultAdapterID = .openAIResponses
        apiKey = ""
        codexCredentialJSON = tokenSet.encoded()
        defaultModel = APIConfigurationEditView.suggestedDefaultModel(for: providerID)
        invalidateFetchedModelCandidates()
    }

    private func signInWithCodexBrowser() {
        isCodexAuthenticating = true
        codexAuthStatusMessage = "Waiting for browser authorization."
        deviceCodeChallenge = nil
        Task { @MainActor in
            defer { isCodexAuthenticating = false }
            do {
                let tokenSet = try await CodexChatGPTOAuthService.signInWithBrowser { url in
                    openURL(url)
                }
                applyCodexToken(tokenSet)
                codexAuthStatusMessage = "Browser sign-in completed."
            } catch {
                codexAuthStatusMessage = error.localizedDescription
            }
        }
    }

    private func signInWithCodexDeviceCode() {
        isCodexAuthenticating = true
        codexAuthStatusMessage = "Requesting device code."
        deviceCodeChallenge = nil
        Task { @MainActor in
            defer { isCodexAuthenticating = false }
            do {
                let challenge = try await CodexChatGPTOAuthService.startDeviceCodeLogin()
                deviceCodeChallenge = challenge
                codexAuthStatusMessage = "Open verification page and enter device code."
                let tokenSet = try await CodexChatGPTOAuthService.completeDeviceCodeLogin(challenge)
                applyCodexToken(tokenSet)
                deviceCodeChallenge = nil
                codexAuthStatusMessage = "Device-code sign-in completed."
            } catch {
                codexAuthStatusMessage = error.localizedDescription
            }
        }
    }

    private func refreshCodexToken() {
        guard let tokenSet = codexTokenSet else { return }
        isCodexAuthenticating = true
        codexAuthStatusMessage = "Refreshing Codex ChatGPT token."
        Task { @MainActor in
            defer { isCodexAuthenticating = false }
            do {
                let refreshed = try await CodexChatGPTOAuthService.refresh(tokenSet)
                applyCodexToken(refreshed)
                codexAuthStatusMessage = "Token refreshed."
            } catch {
                codexAuthStatusMessage = error.localizedDescription
            }
        }
    }

    private func signOutCodex() {
        codexCredentialJSON = "{}"
        codexAuthStatusMessage = "Signed out."
        deviceCodeChallenge = nil
        invalidateFetchedModelCandidates()
    }

    private var localProviderStatusText: String {
        LLMProviderRegistry.shared.localStatusText(for: providerID) ?? "On-device model"
    }
}

/// Preset provider options used to seed API configuration fields.
enum APIPreset: String, CaseIterable {
    case openAI = "OpenAI"
    case codexChatGPTSubscription = "Codex ChatGPT Subscription"
    case appleIntelligence = "Apple Intelligence"
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
        case .codexChatGPTSubscription: return "terminal"
        case .appleIntelligence: return "apple.logo"
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
        case .codexChatGPTSubscription: return .openAICodexChatGPTSubscription
        case .appleIntelligence: return .appleIntelligence
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
        case .openAICodexChatGPTSubscription:
            return .codexChatGPTSubscription
        case .appleIntelligence:
            return .appleIntelligence
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
        }
    }

    var baseURL: String {
        switch self {
        case .openAI: return AppDefaults.OpenAi.baseURL
        case .codexChatGPTSubscription: return CodexChatGPTOAuthService.codexBackendBaseURL
        case .appleIntelligence: return ""
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
