import Observation
import SwiftData
import Foundation

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
        [SortDescriptor(\ModelItem.name)]
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

    // MARK: - Defaults
    var defaultApiConfiguration: APIConfigurationItem? {
        if let explicit = fetchApiConfigurations().first(where: { $0.isDefault }) {
            return explicit
        }
        return fetchApiConfigurations().first
    }

    var defaultWebSearchConfiguration: WebSearchConfigurationItem? {
        if let explicit = fetchWebSearchConfigurations().first(where: { $0.isDefault }) {
            return explicit
        }
        return fetchWebSearchConfigurations().first
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

    func delete<T: PersistentModel>(_ item: T) throws {
        let itemID = item.persistentModelID
        modelContext.delete(item)
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
        if let config = conversation.options.apiConfiguration {
            conversation.options.setupAiRequestArguments(for: config, modelContext: modelContext)
        }
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
        guard let streamParam = conversation.options.parameters.first(where: { $0.name == "stream" }) else {
            throw AppError.invalidOperation("Stream parameter not found")
        }
        streamParam.setValue(enabled)
        streamParam.isEnabled = enabled
        try saveContext()
        vxAtelierPro.log.info("Set streaming to \(enabled) for \(conversation.title)")
    }

    func setModel(_ model: String, for conversation: ConversationItem) throws {
        guard let modelParam = conversation.options.parameters.first(where: { $0.name == "model" }) else {
            throw AppError.invalidOperation("Model parameter not found")
        }
        modelParam.setValue(model)
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
    func fetchModelsFromProviders() async {
        let apiConfigurations = fetchApiConfigurations()
        var updated = 0
        var added = 0

        for config in apiConfigurations {
            let service = AIServiceManager.shared.getService(with: config)
            var fetchedModels: [AIModel] = []

            do {
                fetchedModels = try await service.fetchAvailableModels()
            } catch {
                vxAtelierPro.log.error(
                    "Failed to fetch models from provider \(config.name): \(error.localizedDescription)")
                fetchedModels = service.getDefaultModels()
            }

            let existingModels = fetchModels()
            for fetchedModel in fetchedModels {
                if let existing = existingModels.first(where: { $0.name == fetchedModel.id }) {
                    existing.contextSize = fetchedModel.contextSize
                    existing.provider = fetchedModel.provider
                    existing.capabilities = fetchedModel.capabilities
                    updated += 1
                    vxAtelierPro.log.debug("Overwrote model: \(fetchedModel.id)")
                } else {
                    let modelItem = ModelItem(
                        name: fetchedModel.id,
                        contextSize: fetchedModel.contextSize,
                        provider: fetchedModel.provider
                    )
                    modelItem.capabilities = fetchedModel.capabilities
                    modelContext.insert(modelItem)
                    added += 1
                    vxAtelierPro.log.debug("Added new model: \(fetchedModel.id)")
                }
            }
        }

        do {
            try self.saveContext()
            vxAtelierPro.log.info(
                "fetchModelsFromProviders: Updated \(updated), added \(added) models.")
        } catch {
            vxAtelierPro.log.error("fetchModelsFromProviders failed: \(error.localizedDescription)")
        }
    }
}

protocol StatusModifiable: PersistentModel {
    var status: ItemStatus { get set }
}

extension ConversationItem: StatusModifiable {}
extension ProjectItem: StatusModifiable {}
