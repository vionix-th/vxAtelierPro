import Combine
import Observation
import SwiftData
import SwiftUI

/// Centralized manager for all SwiftData queries in the application
/// This class acts as a single source of truth for data access throughout the app
@Observable
@MainActor
final class QueryManager: @unchecked Sendable {
    // MARK: - Model Context
    private let modelContext: ModelContext

    // MARK: - Published Properties
    // These are all conversations and projects, regardless of filtering
    var allConversations: [ConversationItem] = []
    var allProjects: [ProjectItem] = []

    // These remain private as they're only used internally for filtering
    private var allBookmarks: [BookmarkItem] = []
    private var allApiConfigurations: [APIConfigurationItem] = []
    private var allPromptTemplates: [PromptTemplate] = []
    private var allVoiceConfigurations: [VoiceConfigurationItem] = []
    private var allModels: [ModelItem] = []
    private var allWebSearchConfigurations: [WebSearchConfigurationItem] = []

    // MARK: - Fetch Descriptors
    private let conversationDescriptor: FetchDescriptor<ConversationItem>
    private let projectsDescriptor: FetchDescriptor<ProjectItem>
    private let bookmarksDescriptor: FetchDescriptor<BookmarkItem>
    private let apiConfigurationsDescriptor: FetchDescriptor<APIConfigurationItem>
    private let promptTemplatesDescriptor: FetchDescriptor<PromptTemplate>
    private let voiceConfigurationsDescriptor: FetchDescriptor<VoiceConfigurationItem>
    private let modelsDescriptor: FetchDescriptor<ModelItem>
    private let webSearchConfigurationsDescriptor: FetchDescriptor<WebSearchConfigurationItem>

    // MARK: - User Preferences (for filtering)
    // Use @ObservationIgnored to prevent conflict with AppStorage's own property wrappers
    @ObservationIgnored @AppStorage("ShowUserDialogsOnly")
    private var appStorageShowUserDialogsOnly: Bool = true {
        didSet {
            refreshFilteredData()
        }
    }

    @ObservationIgnored @AppStorage("ShowArchived")
    private var appStorageShowArchived: Bool = false {
        didSet {
            if appStorageShowArchived {
                appStorageShowTrashed = false
            }
            refreshFilteredData()
        }
    }

    @ObservationIgnored @AppStorage("ShowTrashed")
    private var appStorageShowTrashed: Bool = false {
        didSet {
            if appStorageShowTrashed {
                appStorageShowArchived = false
            }
            refreshFilteredData()
        }
    }

    // Public read-only computed properties to access the AppStorage values
    var showUserDialogsOnly: Bool { appStorageShowUserDialogsOnly }
    var showArchived: Bool { appStorageShowArchived }
    var showTrashed: Bool { appStorageShowTrashed }

    // For updating after context changes
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Initialize descriptors with sorting
        self.conversationDescriptor = FetchDescriptor<ConversationItem>(sortBy: [
            SortDescriptor(\ConversationItem.timestamp, order: .reverse)
        ])
        self.projectsDescriptor = FetchDescriptor<ProjectItem>(sortBy: [
            SortDescriptor(\ProjectItem.name)
        ])
        self.bookmarksDescriptor = FetchDescriptor<BookmarkItem>(sortBy: [
            SortDescriptor(\BookmarkItem.label)
        ])
        self.apiConfigurationsDescriptor = FetchDescriptor<APIConfigurationItem>(sortBy: [
            SortDescriptor(\APIConfigurationItem.name)
        ])
        self.promptTemplatesDescriptor = FetchDescriptor<PromptTemplate>(sortBy: [
            SortDescriptor(\PromptTemplate.name)
        ])
        self.voiceConfigurationsDescriptor = FetchDescriptor<VoiceConfigurationItem>(sortBy: [
            SortDescriptor(\VoiceConfigurationItem.language)
        ])
        self.modelsDescriptor = FetchDescriptor<ModelItem>(sortBy: [SortDescriptor(\ModelItem.name)]
        )
        self.webSearchConfigurationsDescriptor = FetchDescriptor<WebSearchConfigurationItem>(
            sortBy: [SortDescriptor(\WebSearchConfigurationItem.name)])

        // Initial fetch of all data
        fetchAllData()

        // Listen for model context changes
        NotificationCenter.default
            .publisher(for: NSNotification.Name("NSPersistentStoreRemoteChangeNotification"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.fetchAllData()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Fetching

    /// Force a refresh to ensure data is up to date
    func refresh() {
        fetchAllData()
    }

    /// Fetch fresh data from SwiftData
    func fetchAllData() {
        do {
            vxAtelierPro.log.debug("Fetching all data")

            allConversations = try modelContext.fetch(conversationDescriptor)
            allProjects = try modelContext.fetch(projectsDescriptor)
            allBookmarks = try modelContext.fetch(bookmarksDescriptor)
            allApiConfigurations = try modelContext.fetch(apiConfigurationsDescriptor)
            allPromptTemplates = try modelContext.fetch(promptTemplatesDescriptor)
            allVoiceConfigurations = try modelContext.fetch(voiceConfigurationsDescriptor)
            allModels = try modelContext.fetch(modelsDescriptor)
            allWebSearchConfigurations = try modelContext.fetch(webSearchConfigurationsDescriptor)

            // Prime transient caches for bookmarks safely (ID-based, no stale deref)
            primeBookmarkCaches()

            // Update computed properties
            refreshFilteredData()
        } catch {
            vxAtelierPro.log.error("Failed to fetch data: \(error.localizedDescription)")
        }
    }

    /// Refresh filtered data without fetching
    private func refreshFilteredData() {
        // The @Observable property wrapper will automatically notify observers when these properties change
    }

    // MARK: - Computed Properties: Filtered Collections

    /// Standalone conversations that don't belong to a project, filtered by status
    var standaloneConversations: [ConversationItem] {
        allConversations.filter { conversation in
            // First check if conversation belongs to a project
            guard conversation.project == nil else {
                return false
            }

            // Filter by conversation purpose
            if showUserDialogsOnly {
                guard conversation.purpose == .user else {
                    return false
                }
            } else {
                // When showing all conversations, system conversations go to their own section
                guard conversation.purpose != .system else {
                    return false
                }
            }

            // Then apply status filter
            if showArchived {
                return conversation.status == ItemStatus.archived
            }
            if showTrashed {
                return conversation.status == ItemStatus.trashed
            }
            return conversation.status == ItemStatus.active
        }
    }

    /// System conversations, filtered by status
    var systemConversations: [ConversationItem] {
        // If showUserDialogsOnly is true, don't show system conversations at all
        guard !showUserDialogsOnly else {
            return []
        }

        return allConversations.filter { conversation in
            guard conversation.purpose == .system else {
                return false
            }

            if showArchived {
                return conversation.status == ItemStatus.archived
            }
            if showTrashed {
                return conversation.status == ItemStatus.trashed
            }
            return conversation.status == ItemStatus.active
        }
    }

    /// Explicit project status accessors

    var activeProjects: [ProjectItem] {
        allProjects.filter { $0.status == .active }
    }
    var archivedProjects: [ProjectItem] {
        allProjects.filter { $0.status == .archived }
    }
    var trashedProjects: [ProjectItem] {
        allProjects.filter { $0.status == .trashed }
    }

    /// Explicit dialog status accessors
    var activeDialogs: [ConversationItem] {
        allConversations.filter { $0.status == .active }
    }
    var archivedDialogs: [ConversationItem] {
        allConversations.filter { $0.status == .archived }
    }
    var trashedDialogs: [ConversationItem] {
        allConversations.filter { $0.status == .trashed }
    }

    // Privatize ambiguous filter
    private var filteredProjects: [ProjectItem] {
        allProjects.filter { project in
            if showArchived {
                return project.status == ItemStatus.archived
            }
            if showTrashed {
                return project.status == ItemStatus.trashed
            }
            return project.status == ItemStatus.active
        }
    }

    /// Active projects only (for selection in conversations)

    /// All available API configurations
    var apiConfigurations: [APIConfigurationItem] {
        allApiConfigurations
    }

    /// All available voice configurations
    var voiceConfigurations: [VoiceConfigurationItem] {
        allVoiceConfigurations
    }

    /// All available prompt templates
    var promptTemplates: [PromptTemplate] {
        allPromptTemplates
    }

    /// All available bookmarks
    var bookmarks: [BookmarkItem] {
        allBookmarks
    }

    /// All available models
    var models: [ModelItem] {
        allModels
    }

    /// All available Web Search configurations
    var webSearchConfigurations: [WebSearchConfigurationItem] {
        allWebSearchConfigurations
    }

    // MARK: - Bookmark Helpers (ID-based resolution)

    /// Resolve a bookmark's target message ID without touching optional relationships.
    /// Only uses the transient cache set at creation time; otherwise returns nil.
    private func resolvedTargetMessageID(for bookmark: BookmarkItem) -> PersistentIdentifier? {
        bookmark.targetMessageIDCache
    }

    /// Whether the user bubble of a turn is bookmarked.
    func isUserBookmarked(turnID: PersistentIdentifier) -> Bool {
        bookmarks.contains { $0.turn?.id == turnID && $0.target == nil }
    }

    /// Whether a specific assistant message within a turn is bookmarked (by messageID).
    func isAssistantBookmarked(turnID: PersistentIdentifier, messageID: PersistentIdentifier)
        -> Bool
    {
        for b in bookmarks where b.turn?.id == turnID && b.target != nil {
            if let mid = resolvedTargetMessageID(for: b), mid == messageID { return true }
        }
        return false
    }

    /// Compute a scroll hint for a bookmark without dereferencing stale relationships.
    func scrollHint(for bookmark: BookmarkItem) -> PersistentIdentifier? {
        if let tid = resolvedTargetMessageID(for: bookmark) {
            return tid
        }
        // Fallback to user message of the turn
        return bookmark.turn?.userMessage.id
    }

    /// Prime transient caches for bookmarks from the freshly fetched graph.
    /// Intentionally a no-op to avoid dereferencing stale relationships.
    private func primeBookmarkCaches() {}

    /// Dialog linked to the utility panel
    var utilityPanelConversation: ConversationItem? {
        return allConversations.first(where: { $0.isLinkedToUtilityPanel })
    }

    /// Default system conversation
    var systemConversation: ConversationItem? {
        return allConversations.first(where: { $0.purpose == .system })
    }

    /// The default API configuration, determined by the `isDefault` flag or falling back to the first available.
    var defaultApiConfiguration: APIConfigurationItem? {
        if let explicitDefault = allApiConfigurations.first(where: { $0.isDefault }) {
            return explicitDefault
        }
        return allApiConfigurations.first
    }

    /// The default Web Search configuration, determined by the `isDefault` flag or falling back to the first available.
    var defaultWebSearchConfiguration: WebSearchConfigurationItem? {
        if let explicitDefault = allWebSearchConfigurations.first(where: { $0.isDefault }) {
            return explicitDefault
        }
        return allWebSearchConfigurations.first
    }

    /// Ensures the system conversation exists, creating it if necessary.
    /// This should be called after initial data fetch.
    @discardableResult
    func ensureSystemConversation() -> ConversationItem {
        if let existing = allConversations.first(where: { $0.purpose == .system }) {
            return existing
        }

        // Not found, create it
        vxAtelierPro.log.info("System conversation not found, creating a new one.")
        let conversation: ConversationItem
        if let apiConfig = defaultApiConfiguration {
            let options = ConversationOptions(apiConfiguration: apiConfig)
            conversation = ConversationItem("System Dialog", options: options)
        } else {
            conversation = ConversationItem("System Dialog")
        }
        conversation.purpose = .system
        modelContext.insert(conversation)

        // Save and refresh
        do {
            try saveContext()
            // Re-fetch the conversation from the refreshed list to ensure we return the managed instance
            if let newSystemConversation = allConversations.first(where: { $0.purpose == .system })
            {
                return newSystemConversation
            } else {
                // This should theoretically not happen after a successful save and fetch
                vxAtelierPro.log.critical(
                    "Failed to retrieve newly created system conversation after save!")
                // Return the unmanaged instance as a fallback, though it might cause issues
                return conversation
            }
        } catch {
            vxAtelierPro.log.error(
                "Failed to save newly created system conversation: \(error.localizedDescription)")
            // Return the unmanaged instance as a fallback
            return conversation
        }
    }

    // MARK: - Data Mutation Methods

    /// Empties the trash by deleting all trashed items.
    func emptyTrash() throws {
        let trashedItems = allConversations.filter { $0.status == .trashed }
        try deleteItems(trashedItems)

        let trashedProjects = allProjects.filter { $0.status == .trashed }
        try deleteItems(trashedProjects)
    }

    /// Saves the model context with error handling.
    func saveContext() throws {
        do {
            try modelContext.save()
            fetchAllData()  // Refresh data after saving
        } catch {
            vxAtelierPro.log.error("Failed to save ModelContext: \(error.localizedDescription)")
            throw AppError.dataSaveFailed(error.localizedDescription)
        }
    }

    /// Inserts a new persistent model into the context and saves.
    func insert<T: PersistentModel>(_ item: T) throws {
        modelContext.insert(item)
        try saveContext()  // Also refreshes data via fetchAllData
        vxAtelierPro.log.debug("Inserted \(String(describing: T.self)): \(item.persistentModelID)")
        fetchAllData()  // Refresh after insert
    }

    // MARK: - Property Clearing Helper
    private func clearStoredProperty(for type: Any.Type) {
        switch type {
        case is ProjectItem.Type:
            allProjects = []
            allConversations = []  // Also clear conversations, since projects own conversations
            allBookmarks = []  // Bookmarks depend on conversations/projects; clear to avoid stale references during mutations
        case is ConversationItem.Type:
            allProjects = []
            allConversations = []
            allBookmarks = []  // Clear dependent bookmarks to prevent UI from touching deleted targets
        case is BookmarkItem.Type:
            allBookmarks = []
        case is APIConfigurationItem.Type:
            allApiConfigurations = []
        case is PromptTemplate.Type:
            allPromptTemplates = []
        case is VoiceConfigurationItem.Type:
            allVoiceConfigurations = []
        case is ModelItem.Type:
            allModels = []
        case is WebSearchConfigurationItem.Type:
            allWebSearchConfigurations = []
        default:
            break
        }
    }

    /// Deletes a single persistent model from the context and saves.
    func delete<T: PersistentModel>(_ item: T) throws {
        clearStoredProperty(for: T.self)
        let itemID = item.persistentModelID  // Capture ID before deletion
        modelContext.delete(item)
        try saveContext()  // Also refreshes data via fetchAllData
        vxAtelierPro.log.debug("Deleted \(String(describing: T.self)): \(itemID)")
    }

    /// Deletes an array of persistent models from the context in a single transaction and saves.
    func deleteItems(_ items: [any PersistentModel]) throws {
        guard !items.isEmpty else {
            vxAtelierPro.log.debug("deleteItems called with an empty array.")
            return
        }
        // Use a Set of type names to avoid duplicate clears
        var clearedTypes = Set<String>()
        for item in items {
            let type = type(of: item)
            let typeName = String(describing: type)
            if !clearedTypes.contains(typeName) {
                clearStoredProperty(for: type)
                clearedTypes.insert(typeName)
            }
        }
        vxAtelierPro.log.debug("Staging deletion for \(items.count) items.")
        for item in items {
            modelContext.delete(item)
        }
        // Save context once after all deletions are staged
        try saveContext()  // Also refreshes data via fetchAllData
        vxAtelierPro.log.debug("Bulk delete operation saved successfully.")
    }

    /// Inserts an array of persistent models into the context in a single transaction and saves.
    func insertItems(_ items: [any PersistentModel]) throws {
        guard !items.isEmpty else {
            vxAtelierPro.log.debug("insertItems called with an empty array.")
            return
        }

        vxAtelierPro.log.debug("Staging insertion for \(items.count) items.")

        for item in items {
            modelContext.insert(item)
        }

        // Save context once after all insertions are staged
        try saveContext()  // Also refreshes data via fetchAllData
        vxAtelierPro.log.debug("Bulk insert operation saved successfully.")
    }

    /// Updates references when a configuration is deleted **during backup restoration**.
    func cleanupReferences(for config: APIConfigurationItem) throws {
        // Iterate through existing fetched conversations
        for conversation in allConversations
        where conversation.options.apiConfiguration?.id == config.id {
            conversation.options.apiConfiguration = nil
        }

        // Iterate through existing fetched projects
        for project in allProjects where project.defaultOptions.apiConfiguration?.id == config.id {
            project.defaultOptions.apiConfiguration = nil
        }

        // Save changes using the centralized method
        try saveContext()
        // No separate fetch needed, saveContext already refreshes.
    }

    /// Create a new conversation with default settings
    func createConversation() -> ConversationItem {
        let conversation: ConversationItem

        if let apiConfig = defaultApiConfiguration {
            let options = ConversationOptions(apiConfiguration: apiConfig)
            conversation = ConversationItem(AppDefaults.newDialogName, options: options)
        } else {
            conversation = ConversationItem(AppDefaults.newDialogName)
        }

        do {
            try self.insert(conversation)
        } catch {
            // Error already logged by saveContext/insert
            vxAtelierPro.log.error(
                "Failed to insert new conversation: \(error.localizedDescription)")
        }
        return conversation
    }

    /// Create a new project with default settings
    func createProject() -> ProjectItem {
        let project: ProjectItem

        if let apiConfig = defaultApiConfiguration {
            let options = ConversationOptions(apiConfiguration: apiConfig)
            project = ProjectItem(AppDefaults.newProjectName, defaultOptions: options)
        } else {
            project = ProjectItem(AppDefaults.newProjectName)
        }

        do {
            try self.insert(project)
        } catch {
            // Error already logged by saveContext/insert
            vxAtelierPro.log.error("Failed to insert new project: \(error.localizedDescription)")
        }
        return project
    }

    // MARK: - Item Status Actions

    /// Moves an item to the trash.
    func moveItemToTrash(_ item: any PersistentModel) throws {
        guard let modifiableItem = item as? (any StatusModifiable) else {
            vxAtelierPro.log.warning(
                "Attempted to move non-StatusModifiable item to trash: \(type(of: item))")
            // Bookmarks are deleted immediately, handle this case specifically
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

    /// Archives an item.
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

    /// Restores an item to active status.
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

    /// Assigns a conversation to a project (or removes it) and persists the change.
    func assignConversation(_ conversation: ConversationItem, to project: ProjectItem?) throws {
        conversation.project = project
        try saveContext()
        let projectName = project?.name ?? "none"
        vxAtelierPro.log.debug(
            "Assigned conversation '\(conversation.title)' (ID: \(conversation.id)) to project '\(projectName)'."
        )
    }

    /// Permanently deletes an item, handling project cascades.
    func deleteItemPermanently(_ item: any PersistentModel) throws {
        vxAtelierPro.log.debug(
            "Initiating permanent deletion for item (ID: \(item.persistentModelID), Type: \(type(of: item)))."
        )
        try delete(item)  // Handles save and refresh internally
        vxAtelierPro.log.debug(
            "Permanent deletion process complete for item (ID: \(item.persistentModelID)).")
    }

    /// Returns the last turn or event timestamp for a given conversation, or nil if no turns exist
    func lastTurnTimestamp(for conversation: ConversationItem) -> Date? {
        guard
            let lastTurn = conversation.turns.sorted(by: { $0.sequenceNumber < $1.sequenceNumber })
                .last
        else { return nil }
        return lastTurn.events.last?.message.timestamp ?? lastTurn.userMessage.timestamp
    }

    /// Returns the last turn or event timestamp for a given project, or nil if no turns exist
    func lastTurnTimestamp(for project: ProjectItem) -> Date? {
        return project.conversations.compactMap { lastTurnTimestamp(for: $0) }.max()
    }

    /// Returns conversations sorted by last turn/event timestamp
    func sortedConversationByLastTurn(_ conversations: [ConversationItem], descending: Bool)
        -> [ConversationItem]
    {
        return conversations.sorted {
            let lhsDate = lastTurnTimestamp(for: $0) ?? $0.timestamp
            let rhsDate = lastTurnTimestamp(for: $1) ?? $1.timestamp
            return descending ? lhsDate > rhsDate : lhsDate < rhsDate
        }
    }

    // MARK: - Bulk Deletion and Data Reset
    /// Deletes all items of a given PersistentModel type. Returns the number of deleted items.
    func deleteAll<T: PersistentModel>(of type: T.Type) throws -> Int {
        clearStoredProperty(for: T.self)
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items { modelContext.delete(item) }
        try saveContext()
        return items.count
    }

    /// Deletes all ModelItem instances and returns the count.
    func deleteAllModels() throws -> Int {
        return try deleteAll(of: ModelItem.self)
    }

    /// Deletes all user data (except AppStorage/UserDefaults). Does not reset settings.
    func cleanLocalStorage() throws {
        // Clear all arrays before deletion
        clearStoredProperty(for: BookmarkItem.self)
        clearStoredProperty(for: ProjectItem.self)
        clearStoredProperty(for: ConversationItem.self)
        clearStoredProperty(for: APIConfigurationItem.self)
        clearStoredProperty(for: WebSearchConfigurationItem.self)
        clearStoredProperty(for: ModelItem.self)
        clearStoredProperty(for: VoiceConfigurationItem.self)
        clearStoredProperty(for: PromptTemplate.self)
        // 1. Delete bookmarks first as they depend on conversations
        _ = try deleteAll(of: BookmarkItem.self)
        // 2. Delete projects and conversations
        _ = try deleteAll(of: ProjectItem.self)
        _ = try deleteAll(of: ConversationItem.self)
        // 3. Delete configurations
        _ = try deleteAll(of: APIConfigurationItem.self)
        _ = try deleteAll(of: WebSearchConfigurationItem.self)
        // 4. Delete independent items
        _ = try deleteAll(of: ModelItem.self)
        _ = try deleteAll(of: VoiceConfigurationItem.self)
        _ = try deleteAll(of: PromptTemplate.self)
        // Ensure system conversation exists after destructive operations
        ensureSystemConversation()
        refresh()
    }

    /// Inserts a new bookmark for the user message of a turn.
    func insertBookmark(label: String, turn: ConversationTurn) {
        let bookmark = BookmarkItem(label, turn: turn)
        do {
            try insert(bookmark)
        } catch {
            vxAtelierPro.log.error("Failed to insert bookmark: \(error.localizedDescription)")
        }
    }

    /// Inserts a new bookmark for a specific event within a turn.
    func insertBookmark(label: String, turn: ConversationTurn, event: TurnEvent) {
        let bookmark = BookmarkItem(label, turn: turn, event: event)
        do {
            try insert(bookmark)
        } catch {
            vxAtelierPro.log.error("Failed to insert bookmark: \(error.localizedDescription)")
        }
    }

    /// Returns projects sorted for the sidebar according to the given order and type
    func sortedProjectsForSidebar(
        _ projects: [ProjectItem], descending: Bool, sortType: SidebarSortType
    ) -> [ProjectItem] {
        switch sortType {
        case .alphabetically:
            return projects.sorted {
                descending
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        // Add more sort types for projects if needed
        default:
            return projects
        }
    }

    /// Returns conversations sorted for the sidebar according to the given order and type
    func sortedConversationsForSidebar(
        _ conversations: [ConversationItem], descending: Bool, sortType: SidebarSortType
    ) -> [ConversationItem] {
        switch sortType {
        case .conversationDate:
            return conversations.sorted {
                descending ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp
            }
        case .lastMessageDate:
            // Use last turn/event timestamp
            return sortedConversationByLastTurn(conversations, descending: descending)
        case .alphabetically:
            return conversations.sorted {
                descending
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending
                    : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    /// Fetches models from all configured API providers and updates the local store.
    @MainActor
    func fetchModelsFromProviders() async {

        let apiConfigurations = self.apiConfigurations  // Fetch all API configurations
        var updated = 0
        var added = 0

        for config in apiConfigurations {
            let service = AIServiceManager.shared.getService(with: config)
            var fetchedModels: [AIModel] = []

            do {
                fetchedModels = try await service.fetchAvailableModels()
            } catch {
                vxAtelierPro.log.error(
                    "Failed to fetch models from provider \(config.name): \(error.localizedDescription)"
                )
                // fallback to the default model cataloge 
                fetchedModels = service.getDefaultModels()
            }

            for fetchedModel in fetchedModels {
                if let existing = allModels.first(where: { $0.name == fetchedModel.id }) {
                    // Update existing model in place
                    existing.contextSize = fetchedModel.contextSize
                    existing.provider = fetchedModel.provider
                    existing.capabilities = fetchedModel.capabilities
                    updated += 1
                    vxAtelierPro.log.debug("Overwrote model: \(fetchedModel.id)")
                } else {
                    // Insert new model
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

/// Protocol for items that can have their status modified (active, archived, trashed).
protocol StatusModifiable: PersistentModel {
    var status: ItemStatus { get set }
}

// Conform existing models to the protocol
extension ConversationItem: StatusModifiable {}
extension ProjectItem: StatusModifiable {}
