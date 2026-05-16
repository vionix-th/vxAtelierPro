import Observation
import SwiftData
import Foundation

struct ModelProviderFetchFailure: Equatable {
    let configurationName: String
    let providerID: LLMProviderID
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
            vxAtelierPro.log.debug("deleteTurns called with empty messageIDs for conversation \(conversation.id)")
            return 0
        }

        let initialCount = conversation.turns.count
        conversation.turns.removeAll { turn in
            if messageIDs.contains(turn.userMessage.id) { return true }
            return turn.events.contains { messageIDs.contains($0.message.id) }
        }
        let removed = initialCount - conversation.turns.count

        if removed > 0 {
            conversation.forceUpdateTokenCount(updateContextCount: true, updateTotalCount: false)
            try saveContext()
            vxAtelierPro.log.notice("Deleted \(removed) turn(s) from conversation \(conversation.id)")
        } else {
            vxAtelierPro.log.debug("deleteTurns removed 0 turns for conversation \(conversation.id)")
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
            guard bookmark.turn?.id == turn.id else { return false }
            if let event {
                return bookmark.target?.id == event.id
            }
            return bookmark.target == nil
        }
    }

    func insertBookmark(label: String, turn: ConversationTurn) {
        let bookmark = BookmarkItem(label, turn: turn)
        do {
            try insert(bookmark)
        } catch {
            vxAtelierPro.log.error("Failed to insert bookmark: \(error.localizedDescription)")
        }
    }

    func insertBookmark(label: String, turn: ConversationTurn, event: TurnEvent) {
        let bookmark = BookmarkItem(label, turn: turn, event: event)
        do {
            try insert(bookmark)
        } catch {
            vxAtelierPro.log.error("Failed to insert bookmark: \(error.localizedDescription)")
        }
    }

    func isUserBookmarked(turnID: PersistentIdentifier) -> Bool {
        fetchBookmarks().contains { $0.turn?.id == turnID && $0.target == nil }
    }

    func isAssistantBookmarked(turnID: PersistentIdentifier, messageID: PersistentIdentifier)
        -> Bool
    {
        fetchBookmarks().contains {
            $0.turn?.id == turnID && $0.targetMessageIDCache == messageID
        }
    }

    // MARK: - Models
    func fetchModelCandidates(
        providerID: LLMProviderID,
        adapterID: LLMAdapterID,
        configuration: LLMProviderConfiguration
    ) async throws -> [LLMModelDescriptor] {
        let adapter = LLMProviderRegistry.shared.adapter(
            for: adapterID,
            providerID: providerID
        )
        return try await adapter.fetchModels(configuration: configuration)
    }

    @discardableResult
    func upsertModelCandidates(
        _ candidates: [LLMModelDescriptor],
        for apiConfiguration: APIConfigurationItem
    ) throws -> ModelProviderFetchSummary {
        let existingModels = models(for: apiConfiguration)
        var summary = ModelProviderFetchSummary()

        for candidate in candidates {
            if let existing = existingModels.first(where: { $0.modelID == candidate.id }) {
                existing.apiConfiguration = apiConfiguration
                existing.descriptor = candidate
                summary.updated += 1
                vxAtelierPro.log.debug("Overwrote model: \(candidate.id)")
            } else {
                let modelItem = ModelItem(descriptor: candidate, apiConfiguration: apiConfiguration)
                modelContext.insert(modelItem)
                summary.added += 1
                vxAtelierPro.log.debug("Added new model: \(candidate.id)")
            }
        }

        try saveContext()
        return summary
    }

    @discardableResult
    func refreshModels(for apiConfiguration: APIConfigurationItem) async -> ModelProviderFetchSummary {
        let providerID = apiConfiguration.providerIDEnum
        let adapterID = apiConfiguration.defaultAdapterIDEnum
        let providerConfiguration = apiConfiguration.makeLLMProviderConfiguration()
        let credentialState: String
        if case .secret = providerConfiguration.credential {
            credentialState = "present"
        } else {
            credentialState = "missing"
        }

        vxAtelierPro.log.debug(
            "Refreshing models for provider \(apiConfiguration.name): providerID=\(providerID.rawValue), authKind=\(apiConfiguration.authKind), adapter=\(apiConfiguration.defaultAdapterID), baseURL=\(providerConfiguration.baseURL), apiKeyLength=\(apiConfiguration.apiKey.count), credential=\(credentialState)"
        )

        var summary = ModelProviderFetchSummary()

        do {
            let fetchedModels = try await fetchModelCandidates(
                providerID: providerID,
                adapterID: adapterID,
                configuration: providerConfiguration
            )
            summary = try upsertModelCandidates(fetchedModels, for: apiConfiguration)
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
                providerID: providerID,
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
