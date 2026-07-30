import Observation
import SwiftData
import Foundation

struct ModelProviderFetchFailure: Equatable {
    let configurationName: String
    let providerID: LLMProviderID?
    let message: String
}

struct ModelProviderFetchSummary: Equatable {
    var updated = 0
    var added = 0
    var failures: [ModelProviderFetchFailure] = []
}

@Observable
@MainActor
final class QueryManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch helpers
    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            vxAtelierPro.log.error("Fetch failed for \(T.self): \(error.localizedDescription)")
            return []
        }
    }

    private func fetch<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>? = nil,
        sort: [SortDescriptor<T>] = []
    ) -> [T] {
        var descriptor = FetchDescriptor<T>(sortBy: sort)
        descriptor.predicate = predicate
        return fetch(descriptor)
    }

    private var conversationSort: [SortDescriptor<ConversationItem>] {
        [SortDescriptor(\ConversationItem.timestamp, order: .reverse)]
    }

    private var projectSort: [SortDescriptor<ProjectItem>] {
        [SortDescriptor(\ProjectItem.name)]
    }

    private var bookmarkSort: [SortDescriptor<BookmarkItem>] {
        [SortDescriptor(\BookmarkItem.label)]
    }

    private var apiConfigurationSort: [SortDescriptor<APIConfigurationItem>] {
        [SortDescriptor(\APIConfigurationItem.name)]
    }

    private var modelSort: [SortDescriptor<ModelItem>] {
        [SortDescriptor(\ModelItem.modelID)]
    }

    private var webSearchConfigurationSort: [SortDescriptor<WebSearchConfigurationItem>] {
        [SortDescriptor(\WebSearchConfigurationItem.name)]
    }

    // MARK: - Lookups
    func conversation(with id: PersistentIdentifier) -> ConversationItem? {
        var descriptor = FetchDescriptor<ConversationItem>(sortBy: [])
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate { $0.id == id }
        return fetch(descriptor).first
    }

    func project(with id: PersistentIdentifier) -> ProjectItem? {
        var descriptor = FetchDescriptor<ProjectItem>(sortBy: [])
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate { $0.id == id }
        return fetch(descriptor).first
    }

    func model(with id: PersistentIdentifier) -> ModelItem? {
        var descriptor = FetchDescriptor<ModelItem>(sortBy: [])
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate { $0.id == id }
        return fetch(descriptor).first
    }

    func promptTemplate(with id: PersistentIdentifier) -> PromptTemplate? {
        var descriptor = FetchDescriptor<PromptTemplate>(sortBy: [])
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate { $0.id == id }
        return fetch(descriptor).first
    }

    func bookmark(with id: PersistentIdentifier) -> BookmarkItem? {
        var descriptor = FetchDescriptor<BookmarkItem>(sortBy: [])
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate { $0.id == id }
        return fetch(descriptor).first
    }

    func turn(with id: PersistentIdentifier, in conversation: ConversationItem) -> ConversationTurn? {
        conversation.turns.first { $0.persistentModelID == id }
    }

    func turn(with id: PersistentIdentifier, in conversationID: PersistentIdentifier) -> ConversationTurn? {
        guard let conversation = conversation(with: conversationID) else { return nil }
        return turn(with: id, in: conversation)
    }

    func message(with id: PersistentIdentifier, in turn: ConversationTurn) -> MessageItem? {
        if turn.userMessage.persistentModelID == id {
            return turn.userMessage
        }
        return turn.events.first(where: { $0.message.persistentModelID == id })?.message
    }

    private func fetchConversations(predicate: Predicate<ConversationItem>? = nil) -> [ConversationItem] {
        fetch(ConversationItem.self, predicate: predicate, sort: conversationSort)
    }

    private func fetchProjects(predicate: Predicate<ProjectItem>? = nil) -> [ProjectItem] {
        fetch(ProjectItem.self, predicate: predicate, sort: projectSort)
    }

    private func fetchBookmarks(predicate: Predicate<BookmarkItem>? = nil) -> [BookmarkItem] {
        fetch(BookmarkItem.self, predicate: predicate, sort: bookmarkSort)
    }

    private func fetchApiConfigurations() -> [APIConfigurationItem] {
        fetch(APIConfigurationItem.self, sort: apiConfigurationSort)
    }

    private func fetchWebSearchConfigurations() -> [WebSearchConfigurationItem] {
        fetch(WebSearchConfigurationItem.self, sort: webSearchConfigurationSort)
    }

    private func fetchModels() -> [ModelItem] {
        fetch(ModelItem.self, sort: modelSort)
    }

    func normalizeDefaultAPIConfigurations(preferredDefault: APIConfigurationItem? = nil) {
        let configurations = fetchApiConfigurations()
        guard !configurations.isEmpty else { return }
        let selected = preferredDefault
            ?? configurations.first(where: { $0.isDefault })
            ?? configurations.first
        for configuration in configurations {
            configuration.isDefault = configuration.id == selected?.id
        }
    }

    func normalizeDefaultWebSearchConfigurations(preferredDefault: WebSearchConfigurationItem? = nil) {
        let configurations = fetchWebSearchConfigurations()
        guard !configurations.isEmpty else { return }
        let selected = preferredDefault
            ?? configurations.first(where: { $0.isDefault })
            ?? configurations.first
        for configuration in configurations {
            configuration.isDefault = configuration.id == selected?.id
        }
    }

    func models(for apiConfiguration: APIConfigurationItem?) -> [ModelItem] {
        guard let apiConfiguration else { return [] }
        return fetchModels().filter { $0.apiConfiguration?.id == apiConfiguration.id }
    }

    func model(with modelID: String, for apiConfiguration: APIConfigurationItem) -> ModelItem? {
        models(for: apiConfiguration).first { $0.modelID == modelID }
    }

    func selectedModel(for conversation: ConversationItem) -> ModelItem? {
        guard let apiConfiguration = conversation.options.apiConfiguration else { return nil }
        let modelID = conversation.options.selectedModelID ?? apiConfiguration.defaultModelID
        guard let modelID, !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return model(with: modelID, for: apiConfiguration)
    }

    // MARK: - Defaults
    var defaultApiConfiguration: APIConfigurationItem? {
        let configurations = fetchApiConfigurations()
        if let explicit = configurations.first(where: { $0.isDefault }) {
            return explicit
        }
        return configurations.first
    }

    var defaultWebSearchConfiguration: WebSearchConfigurationItem? {
        let configurations = fetchWebSearchConfigurations()
        if let explicit = configurations.first(where: { $0.isDefault }) {
            return explicit
        }
        return configurations.first
    }

    var utilityPanelConversation: ConversationItem? {
        fetchConversations().first(where: { $0.isUtilityConversation })
    }

    var systemConversation: ConversationItem? {
        fetchConversations().first(where: { $0.purpose == .system })
    }

    // MARK: - System Conversation
    @discardableResult
    func ensureSystemConversation() -> ConversationItem? {
        if let existing = systemConversation {
            return existing
        }

        let options: ConversationOptions
        if let apiConfig = defaultApiConfiguration {
            options = ConversationOptions(apiConfiguration: apiConfig)
        } else {
            options = ConversationOptions()
        }

        let conversation = ConversationItem("System Conversation", options: options)
        conversation.purpose = .system
        modelContext.insert(conversation)

        do {
            try saveContext()
            return systemConversation
        } catch {
            vxAtelierPro.log.error("Failed to save newly created system conversation: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Persistence operations
    func saveContext() throws {
        do {
            try modelContext.save()
        } catch {
            vxAtelierPro.log.error("Failed to save ModelContext: \(error.localizedDescription)")
            throw AppError.dataSaveFailed(error.localizedDescription)
        }
    }

    func insert<T: PersistentModel>(_ item: T) throws {
        modelContext.insert(item)
        try saveContext()
        vxAtelierPro.log.debug("Inserted \(String(describing: T.self)): \(item.persistentModelID)")
    }

    func upsertAPIConfiguration(_ configuration: APIConfigurationItem, makeDefault: Bool) throws {
        let providerID = try configuration.requireProviderID()
        let adapterID = try configuration.requireAdapterID()
        let providerConfiguration = try configuration.makeLLMProviderConfiguration()
        _ = try LLMProviderRegistry.shared.resolveRoute(
            adapterID: adapterID,
            providerID: providerID,
            modelID: configuration.defaultModelID,
            configuration: providerConfiguration
        )
        if configuration.modelContext == nil {
            modelContext.insert(configuration)
        }
        normalizeDefaultAPIConfigurations(preferredDefault: makeDefault ? configuration : nil)
        try saveContext()
    }

    func upsertWebSearchConfiguration(_ configuration: WebSearchConfigurationItem, makeDefault: Bool) throws {
        if configuration.modelContext == nil {
            modelContext.insert(configuration)
        }
        normalizeDefaultWebSearchConfigurations(preferredDefault: makeDefault ? configuration : nil)
        try saveContext()
    }

    func delete<T: PersistentModel>(_ item: T) throws {
        let itemID = item.persistentModelID
        modelContext.delete(item)
        if item is APIConfigurationItem {
            normalizeDefaultAPIConfigurations()
        } else if item is WebSearchConfigurationItem {
            normalizeDefaultWebSearchConfigurations()
        }
        try saveContext()
        vxAtelierPro.log.debug("Deleted \(String(describing: T.self)): \(itemID)")
    }

    func deleteItems(_ items: [any PersistentModel]) throws {
        guard !items.isEmpty else {
            vxAtelierPro.log.debug("deleteItems called with an empty array.")
            return
        }
        vxAtelierPro.log.debug("Staging deletion for \(items.count) items.")
        for item in items {
            modelContext.delete(item)
        }
        try saveContext()
        vxAtelierPro.log.debug("Bulk delete operation saved successfully.")
    }

    // Delete conversation turns containing any of the given message IDs.
    // Returns the number of turns removed.
    func deleteTurns(containing messageIDs: Set<PersistentIdentifier>, in conversation: ConversationItem) throws -> Int {
        guard !messageIDs.isEmpty else {
            vxAtelierPro.log.debug("deleteTurns called with empty messageIDs for conversation \(conversation.persistentModelID)")
            return 0
        }

        let initialCount = conversation.turns.count
        conversation.turns.removeAll { turn in
            if messageIDs.contains(turn.userMessage.persistentModelID) { return true }
            return turn.events.contains { messageIDs.contains($0.message.persistentModelID) }
        }
        let removed = initialCount - conversation.turns.count

        if removed > 0 {
            conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
            try saveContext()
            vxAtelierPro.log.notice("Deleted \(removed) turn(s) from conversation \(conversation.persistentModelID)")
        } else {
            vxAtelierPro.log.debug("deleteTurns removed 0 turns for conversation \(conversation.persistentModelID)")
        }
        return removed
    }

    // MARK: - Cleanup & Deletion
    func emptyTrash() throws {
        let trashedConversations = fetchConversations().filter { $0.status == .trashed }
        try deleteItems(trashedConversations)

        let trashedProjects = fetchProjects().filter { $0.status == .trashed }
        try deleteItems(trashedProjects)
    }

    func deleteItemPermanently(_ item: any PersistentModel) throws {
        vxAtelierPro.log.debug(
            "Initiating permanent deletion for item (ID: \(item.persistentModelID), Type: \(type(of: item)))."
        )
        try delete(item)
        vxAtelierPro.log.debug(
            "Permanent deletion process complete for item (ID: \(item.persistentModelID)).")
    }

    func deleteAll<T: PersistentModel>(of type: T.Type) throws -> Int {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items { modelContext.delete(item) }
        try saveContext()
        return items.count
    }

    func deleteAllModels() throws -> Int {
        try deleteAll(of: ModelItem.self)
    }

    func cleanLocalStorage() throws {
        _ = try deleteAll(of: BookmarkItem.self)
        _ = try deleteAll(of: ProjectItem.self)
        _ = try deleteAll(of: ConversationItem.self)
        _ = try deleteAll(of: APIConfigurationItem.self)
        _ = try deleteAll(of: WebSearchConfigurationItem.self)
        _ = try deleteAll(of: ModelItem.self)
        _ = try deleteAll(of: VoiceConfigurationItem.self)
        _ = try deleteAll(of: TTSPlaylistEntry.self)
        _ = try deleteAll(of: TTSPlaylist.self)
        _ = try deleteAll(of: PromptTemplate.self)
        ensureSystemConversation()
    }

    // MARK: - Creation
    func createConversation(in project: ProjectItem? = nil) throws -> ConversationItem {
        let options: ConversationOptions
        if let project {
            options = project.defaultOptions.copy()
        } else if let apiConfig = defaultApiConfiguration {
            options = ConversationOptions(apiConfiguration: apiConfig)
        } else {
            options = ConversationOptions()
        }

        let conversation = ConversationItem(AppDefaults.newConversationName, options: options)
        conversation.project = project
        modelContext.insert(conversation)

        do {
            try saveContext()
            return conversation
        } catch {
            vxAtelierPro.log.error("Failed to insert new conversation: \(error.localizedDescription)")
            throw error
        }
    }

    func createProject() throws -> ProjectItem {
        let project: ProjectItem
        if let apiConfig = defaultApiConfiguration {
            let options = ConversationOptions(apiConfiguration: apiConfig)
            project = ProjectItem(AppDefaults.newProjectName, defaultOptions: options)
        } else {
            project = ProjectItem(AppDefaults.newProjectName)
        }
        modelContext.insert(project)
        do {
            try saveContext()
            return project
        } catch {
            vxAtelierPro.log.error("Failed to insert new project: \(error.localizedDescription)")
            throw error
        }
    }

    @discardableResult
    func ensureUtilityPanelConversation() throws -> ConversationItem {
        if let existing = utilityPanelConversation {
            return existing
        }

        let conversation = try createConversation()
        conversation.title = AppDefaults.newConversationName
        try setUtilityPanelConversation(conversation, isLinked: true)
        return conversation
    }

    // MARK: - Status Changes
    func moveItemToTrash(_ item: any PersistentModel) throws {
        guard let modifiableItem = item as? (any StatusModifiable) else {
            vxAtelierPro.log.warning(
                "Attempted to move non-StatusModifiable item to trash: \(type(of: item))")
            if item is BookmarkItem {
                try delete(item)
                vxAtelierPro.log.debug(
                    "Deleted BookmarkItem directly as 'move to trash' is not applicable.")
            } else {
                throw AppError.invalidOperation("Item cannot be moved to trash.")
            }
            return
        }

        modifiableItem.status = .trashed
        vxAtelierPro.log.debug("Moved item (ID: \(item.persistentModelID)) to trash.")
        try saveContext()
    }

    func archiveItem(_ item: any PersistentModel) throws {
        guard let modifiableItem = item as? (any StatusModifiable) else {
            vxAtelierPro.log.warning(
                "Attempted to archive non-StatusModifiable item: \(type(of: item))")
            throw AppError.invalidOperation("Item cannot be archived.")
        }

        modifiableItem.status = .archived
        vxAtelierPro.log.debug("Archived item (ID: \(item.persistentModelID)).")
        try saveContext()
    }

    func restoreItem(_ item: any PersistentModel) throws {
        guard let modifiableItem = item as? (any StatusModifiable) else {
            vxAtelierPro.log.warning(
                "Attempted to restore non-StatusModifiable item: \(type(of: item))")
            throw AppError.invalidOperation("Item cannot be restored.")
        }

        modifiableItem.status = .active
        vxAtelierPro.log.debug("Restored item (ID: \(item.persistentModelID)) to active.")
        try saveContext()
    }

    func assignConversation(_ conversation: ConversationItem, to project: ProjectItem?) throws {
        conversation.project = project
        try saveContext()
        let projectName = project?.name ?? "none"
        vxAtelierPro.log.debug(
            "Assigned conversation '\(conversation.title)' (ID: \(conversation.id)) to project '\(projectName)'."
        )
    }

    func setUtilityPanelConversation(_ conversation: ConversationItem, isLinked: Bool) throws {
        for item in fetchConversations() where item.isUtilityConversation && item.id != conversation.id {
            item.isUtilityConversation = false
        }
        conversation.isUtilityConversation = isLinked
        try saveContext()
        vxAtelierPro.log.debug(
            "Set utility panel link for conversation '\(conversation.title)' to \(isLinked)."
        )
    }

    func setStreamingEnabled(_ enabled: Bool, for conversation: ConversationItem) throws {
        conversation.options.setStreamMode(enabled ? .enabled : .disabled)
        try saveContext()
        vxAtelierPro.log.info("Set streaming to \(enabled) for \(conversation.title)")
    }

    func setModel(_ model: String, for conversation: ConversationItem) throws {
        conversation.options.setSelectedModelID(model)
        try saveContext()
        vxAtelierPro.log.info("Updated model to \(model) for \(conversation.title)")
    }

    // MARK: - Reference Cleanup
    func cleanupReferences(for config: APIConfigurationItem) throws {
        let conversations = fetchConversations()
        for conversation in conversations where conversation.options.apiConfiguration?.id == config.id {
            conversation.options.apiConfiguration = nil
        }

        let projects = fetchProjects()
        for project in projects where project.defaultOptions.apiConfiguration?.id == config.id {
            project.defaultOptions.apiConfiguration = nil
        }

        try saveContext()
    }

    // MARK: - Bookmarks
    func bookmark(for turn: ConversationTurn, event: TurnEvent?) -> BookmarkItem? {
        fetchBookmarks().first { bookmark in
            guard bookmark.turn?.persistentModelID == turn.persistentModelID else { return false }
            if let event {
                return bookmark.target?.persistentModelID == event.persistentModelID
            }
            return bookmark.target == nil
        }
    }

    func insertBookmark(
        label: String,
        conversationID: PersistentIdentifier,
        turnID: PersistentIdentifier,
        messageID: PersistentIdentifier
    ) throws {
        guard let conversation = conversation(with: conversationID) else {
            throw AppError.invalidOperation("Conversation not available")
        }
        guard let turn = turn(with: turnID, in: conversation) else {
            throw AppError.invalidOperation("Turn not available")
        }
        guard let message = message(with: messageID, in: turn) else {
            throw AppError.invalidOperation("Message not available")
        }

        if turn.userMessage.persistentModelID == message.persistentModelID {
            try insert(BookmarkItem(label, turn: turn))
        } else if let event = turn.events.first(where: {
            $0.message.persistentModelID == message.persistentModelID
        }) {
            try insert(BookmarkItem(label, turn: turn, event: event))
        } else {
            throw AppError.invalidOperation("Message not available")
        }
    }

    // MARK: - Models
    @discardableResult
    func importModel(
        _ exportData: ModelExportData,
        apiConfigurations: [APIConfigurationItem]
    ) throws -> ModelItem {
        let model = try exportData.toDataItem(apiConfigurations: apiConfigurations)
        guard let apiConfiguration = model.apiConfiguration else {
            throw LLMProviderError.invalidConfiguration("Imported model has no matching API configuration.")
        }
        let providerID = try apiConfiguration.requireProviderID()
        let adapterID = try apiConfiguration.requireAdapterID()
        try validateParameterOverrides(
            model.parameterOverrides.map { ($0.adapterID, $0.parameterID, $0.overrides) },
            providerID: providerID,
            adapterID: adapterID,
            modelID: model.modelID,
            metadata: model.providerMetadata
        )
        modelContext.insert(model)
        try saveContext()
        return model
    }

    func updateModelProfile(
        _ model: ModelItem,
        modelID: String,
        apiConfiguration: APIConfigurationItem,
        displayNameOverride: String?,
        contextSizeOverride: Int?,
        capabilityOverrides: [LLMModelCapability: LLMSupportState],
        parameterOverrides: [(LLMAdapterID, LLMParameterID, LLMParameterOverrides)]
    ) throws {
        let normalizedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModelID.isEmpty else {
            throw LLMProviderError.invalidConfiguration("Model ID is required.")
        }
        let providerID = try apiConfiguration.requireProviderID()
        let adapterID = try apiConfiguration.requireAdapterID()
        try validateParameterOverrides(
            parameterOverrides,
            providerID: providerID,
            adapterID: adapterID,
            modelID: normalizedModelID,
            metadata: model.providerMetadata
        )
        model.modelID = normalizedModelID
        model.apiConfiguration = apiConfiguration
        model.displayNameOverride = normalizedOptional(displayNameOverride)
        model.contextSizeOverride = contextSizeOverride

        for item in model.capabilityOverrides { modelContext.delete(item) }
        for item in model.parameterOverrides { modelContext.delete(item) }
        model.capabilityOverrides = capabilityOverrides
            .filter { $0.value != .unknown }
            .map { ModelCapabilityOverrideItem(capability: $0.key, support: $0.value) }
        model.parameterOverrides = parameterOverrides.compactMap { adapterID, parameterID, overrides in
            let kind: ModelDefaultValueOverrideKind
            let value: JSONValue?
            switch overrides.defaultValue {
            case .inherit:
                kind = .inherit
                value = nil
            case .value(let overriddenValue):
                kind = .value
                value = overriddenValue
            case .none:
                kind = .none
                value = nil
            }
            let optionsKind: ModelDefaultValueOverrideKind
            let options: [String]?
            switch overrides.options {
            case .inherit:
                optionsKind = .inherit
                options = nil
            case .value(let value):
                optionsKind = .value
                options = value
            case .none:
                optionsKind = .none
                options = nil
            }
            let item = ModelParameterOverrideItem(
                adapterID: adapterID,
                parameterID: parameterID,
                support: overrides.support,
                mapping: overrides.mapping,
                requiredOverride: overrides.isRequired,
                enabledByDefaultOverride: overrides.isEnabledByDefault,
                defaultValueOverrideKind: kind,
                defaultValue: value,
                optionsOverrideKind: optionsKind,
                options: options
            )
            return item.isEmpty ? nil : item
        }

        if model.modelContext == nil {
            modelContext.insert(model)
        }
        try saveContext()
    }

    private func validateParameterOverrides(
        _ overrides: [(LLMAdapterID, LLMParameterID, LLMParameterOverrides)],
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        modelID: String,
        metadata: LLMProviderModelMetadata
    ) throws {
        var identities = Set<String>()
        for (overrideAdapterID, parameterID, override) in overrides {
            let identity = "\(overrideAdapterID.rawValue):\(parameterID.rawValue)"
            guard identities.insert(identity).inserted else {
                throw LLMProviderError.invalidConfiguration(
                    "Only one override is allowed for \(parameterID.rawValue) on \(overrideAdapterID.displayName)."
                )
            }
            guard override.support != .unknown else {
                throw LLMProviderError.invalidConfiguration(
                    "\(parameterID.rawValue) must inherit instead of overriding support to unknown."
                )
            }
            if let mapping = override.mapping {
                guard overrideAdapterID == mapping.adapterID,
                      parameterID == mapping.parameterID else {
                    throw LLMProviderError.invalidConfiguration("Parameter override and mapping identities do not match.")
                }
                switch mapping.encodingKind {
                case .adapter:
                    throw LLMProviderError.invalidConfiguration(
                        "Adapter-owned mappings cannot be created as user overrides."
                    )
                case .key:
                    guard overrideAdapterID.supportsKeyParameterMappings else {
                        throw LLMProviderError.invalidConfiguration(
                            "\(overrideAdapterID.displayName) does not support key parameter mappings."
                        )
                    }
                    guard !mapping.wireKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LLMProviderError.invalidConfiguration(
                            "\(parameterID.rawValue) requires a non-empty wire key."
                        )
                    }
                case .preset:
                    guard let preset = mapping.structuredPreset, preset.supports(overrideAdapterID) else {
                        throw LLMProviderError.invalidConfiguration(
                            "\(parameterID.rawValue) requires a preset supported by \(overrideAdapterID.displayName)."
                        )
                    }
                }
            }
        }

        let adapterIDs = Set(overrides.map { $0.0 }).union([adapterID])
        for resolvedAdapterID in adapterIDs {
            let selectedOverrides = overrides
                .filter { $0.0 == resolvedAdapterID }
                .reduce(into: [LLMParameterID: LLMParameterOverrides]()) { result, entry in
                    result[entry.1] = entry.2
                }
            let profile = LLMModelProfileResolver(
                fallbackContextSize: AppDefaults.ModelContextSizes.defaultSize
            ).resolve(
                providerID: providerID,
                adapterID: resolvedAdapterID,
                modelID: modelID,
                metadata: metadata,
                overrides: LLMModelOverrides(parameterOverrides: selectedOverrides)
            )
            for (overrideAdapterID, parameterID, override) in overrides
                where overrideAdapterID == resolvedAdapterID && override.support == .supported {
                guard profile.parameters[parameterID]?.support.state == .supported,
                      profile.parameters[parameterID]?.mapping != nil else {
                    throw LLMProviderError.invalidConfiguration(
                        "\(parameterID.rawValue) cannot be supported without an inherited or overridden mapping."
                    )
                }
            }
            for (overrideAdapterID, parameterID, override) in overrides
                where overrideAdapterID == resolvedAdapterID && override.isRequired == true {
                guard profile.parameters[parameterID]?.support.state == .supported else {
                    throw LLMProviderError.invalidConfiguration(
                        "\(parameterID.rawValue) cannot be required while unsupported."
                    )
                }
            }
        }
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func fetchModelMetadata(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMProviderModelMetadata] {
        try await LLMProviderRegistry.shared.fetchModelMetadata(
            adapterID: adapterID,
            providerID: providerID,
            configuration: configuration
        )
    }

    @discardableResult
    func upsertModelMetadata(
        _ metadata: [LLMProviderModelMetadata],
        for apiConfiguration: APIConfigurationItem
    ) throws -> ModelProviderFetchSummary {
        let existingModels = models(for: apiConfiguration)
        var summary = ModelProviderFetchSummary()

        for modelMetadata in metadata {
            if let existing = existingModels.first(where: { $0.modelID == modelMetadata.id }) {
                existing.apiConfiguration = apiConfiguration
                existing.apply(modelMetadata)
                summary.updated += 1
                vxAtelierPro.log.debug("Updated provider model metadata: \(modelMetadata.id)")
            } else {
                let modelItem = ModelItem(metadata: modelMetadata, apiConfiguration: apiConfiguration)
                modelContext.insert(modelItem)
                summary.added += 1
                vxAtelierPro.log.debug("Added provider model metadata: \(modelMetadata.id)")
            }
        }

        try saveContext()
        return summary
    }

    @discardableResult
    func refreshModels(for apiConfiguration: APIConfigurationItem) async -> ModelProviderFetchSummary {
        var summary = ModelProviderFetchSummary()

        do {
            let providerID = try apiConfiguration.requireProviderID()
            let adapterID = try apiConfiguration.requireAdapterID()
            let providerConfiguration = try apiConfiguration.makeLLMProviderConfiguration()
            let credentialState: String
            if case .secret = providerConfiguration.credential {
                credentialState = "present"
            } else {
                credentialState = "missing"
            }

            vxAtelierPro.log.debug(
                "Refreshing models for provider \(apiConfiguration.name): providerID=\(providerID.rawValue), authKind=\(apiConfiguration.authKind), adapter=\(apiConfiguration.adapterID), baseURL=\(providerConfiguration.baseURL), apiKeyLength=\(apiConfiguration.apiKey.count), credential=\(credentialState)"
            )
            let fetchedModels = try await fetchModelMetadata(
                providerID: providerID,
                adapterID: adapterID,
                configuration: providerConfiguration
            )
            summary = try upsertModelMetadata(fetchedModels, for: apiConfiguration)
            vxAtelierPro.log.info(
                "refreshModels(for: \(apiConfiguration.name)): Updated \(summary.updated), added \(summary.added) models."
            )
        } catch {
            let message = Self.errorMessage(from: error)
            vxAtelierPro.log.error(
                "Failed to refresh models for provider \(apiConfiguration.name): \(message)"
            )
            summary.failures.append(ModelProviderFetchFailure(
                configurationName: apiConfiguration.name,
                providerID: apiConfiguration.parsedProviderID,
                message: message
            ))
        }

        return summary
    }

    @discardableResult
    func fetchModelsFromProviders() async -> ModelProviderFetchSummary {
        let apiConfigurations = fetchApiConfigurations()
        var summary = ModelProviderFetchSummary()

        for config in apiConfigurations {
            let result = await refreshModels(for: config)
            summary.updated += result.updated
            summary.added += result.added
            summary.failures.append(contentsOf: result.failures)
        }

        vxAtelierPro.log.info(
            "fetchModelsFromProviders: Updated \(summary.updated), added \(summary.added) models, failures \(summary.failures.count).")
        return summary
    }

    private static func errorMessage(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

protocol StatusModifiable: PersistentModel {
    var status: ItemStatus { get set }
}

extension ConversationItem: StatusModifiable {}
extension ProjectItem: StatusModifiable {}
