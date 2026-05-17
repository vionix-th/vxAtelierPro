import SwiftData
import SwiftUI

// MARK: - ContentView
struct ContentView: View {
    // MARK: - Environment & Context
    @Environment(QueryManager.self) private var queryManager
    @Environment(NavigationRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @Query(sort: [SortDescriptor(\ProjectItem.name)]) private var projects: [ProjectItem]
    @Query(sort: [SortDescriptor(\ConversationItem.timestamp, order: .reverse)]) private var conversations: [ConversationItem]
    @Query(sort: [SortDescriptor(\BookmarkItem.label)]) private var bookmarks: [BookmarkItem]
    
    // MARK: - View Options (UserDefaults-backed)
    @AppStorage(AppSettings.Keys.showEmptySections) private var showEmptySections: Bool = AppDefaults.showEmptySections
    @AppStorage(AppSettings.Keys.showSystemConversations) private var showSystemConversations: Bool = AppDefaults.showSystemConversations
    @AppStorage(AppSettings.Keys.contentFilter) private var contentFilter: ContentFilter = .active
    @AppStorage(AppSettings.Keys.sidebarConversationsSortDescending) private var sidebarConversationsSortDescending: Bool = true
    @AppStorage(AppSettings.Keys.sidebarConversationsSortType) private var sidebarConversationsSortTypeRaw: String =
    SidebarSortType.conversationDate.rawValue
    @AppStorage(AppSettings.Keys.sidebarProjectsSortDescending) private var sidebarProjectsSortDescending: Bool = false
    @AppStorage(AppSettings.Keys.sidebarProjectsSortType) private var sidebarProjectsSortTypeRaw: String =
    SidebarSortType.alphabetically.rawValue
    
    // MARK: - State & Bindings
    let onRequestOptions: (PersistentIdentifier) -> Void
    let onRequestExportProject: (ProjectItem) -> Void
    let onRequestExportConversation: (ConversationItem) -> Void
    let onRequestImport: () -> Void
    let onRequestSettings: (SettingsDestination?) -> Void
    let onRequestTTS: () -> Void
    let onRequestLogHistory: () -> Void
    
    private var filteredProjects: [ProjectItem] {
        switch contentFilter {
        case .active:
            return projects.filter { $0.status == .active }
        case .archived:
            return projects.filter { $0.status == .archived }
        case .trashed:
            return projects.filter { $0.status == .trashed }
        }
    }
    
    private var standaloneConversations: [ConversationItem] {
        conversations.filter { conversation in
            guard conversation.project == nil else { return false }
            switch contentFilter {
            case .active:
                if conversation.status != .active { return false }
            case .archived:
                if conversation.status != .archived { return false }
            case .trashed:
                if conversation.status != .trashed { return false }
            }
            if !showSystemConversations && conversation.purpose == .system {
                return false
            }
            return true
        }
    }
    
    private var visibleBookmarks: [BookmarkItem] {
        contentFilter == .active ? bookmarks : []
    }
    
    private var hasVisibleSidebarItems: Bool {
        !filteredProjects.isEmpty || !standaloneConversations.isEmpty || !visibleBookmarks.isEmpty
    }
    
    private var trashedConversationsCount: Int {
        conversations.filter { $0.status == .trashed && $0.project == nil }.count
    }
    
    private var trashedProjectsCount: Int {
        projects.filter { $0.status == .trashed }.count
    }
    
    private var archivedConversationsCount: Int {
        conversations.filter { $0.status == .archived && $0.project == nil }.count
    }
    
    private var archivedProjectsCount: Int {
        projects.filter { $0.status == .archived }.count
    }
    
    // MARK: - Helper Methods
    // MARK: - Actions
    private func addConversation() {
        do {
            let conversation = try queryManager.createConversation()
            router.setSelection(.conversation(conversation.id))
        } catch {
            vxAtelierPro.log.error("Failed to create conversation: \(error.localizedDescription)")
        }
    }

    private func addConversationAndOpenOptions() {
        do {
            let conversation = try queryManager.createConversation()
            router.setSelection(.conversation(conversation.id))
            onRequestOptions(conversation.id)
        } catch {
            vxAtelierPro.log.error("Failed to create conversation: \(error.localizedDescription)")
        }
    }
    
    private func addProject() {
        do {
            let project = try queryManager.createProject()
            router.setSelection(.project(project.id))
        } catch {
            vxAtelierPro.log.error("Failed to create project: \(error.localizedDescription)")
        }
    }
    
    private func deleteProject(id: PersistentIdentifier) {
        guard let project = queryManager.project(with: id) else { return }
        deleteItem(for: project)
    }
    
    private func restoreProject(id: PersistentIdentifier) {
        guard let project = queryManager.project(with: id) else { return }
        restoreItem(project)
    }
    
    private func archiveProject(id: PersistentIdentifier) {
        guard let project = queryManager.project(with: id) else { return }
        archiveItem(project)
    }
    
    private func renameProject(id: PersistentIdentifier, newTitle: String) {
        guard let project = queryManager.project(with: id) else { return }
        project.name = newTitle
        do {
            try queryManager.saveContext()
        } catch {
            vxAtelierPro.log.error(
                "ContentView: Failed to rename project '\(project.name)': \(error.localizedDescription)"
            )
        }
    }
    
    private func requestExportProject(id: PersistentIdentifier) {
        guard let project = queryManager.project(with: id) else { return }
        onRequestExportProject(project)
    }
    
    private func deleteConversation(id: PersistentIdentifier) {
        guard let conversation = queryManager.conversation(with: id) else { return }
        deleteItem(for: conversation)
    }
    
    private func restoreConversation(id: PersistentIdentifier) {
        guard let conversation = queryManager.conversation(with: id) else { return }
        restoreItem(conversation)
    }
    
    private func archiveConversation(id: PersistentIdentifier) {
        guard let conversation = queryManager.conversation(with: id) else { return }
        archiveItem(conversation)
    }
    
    private func renameConversation(id: PersistentIdentifier, newTitle: String) {
        guard let conversation = queryManager.conversation(with: id) else { return }
        conversation.title = newTitle
        do {
            try queryManager.saveContext()
        } catch {
            vxAtelierPro.log.error(
                "ContentView: Failed to rename conversation '\(conversation.title)': \(error.localizedDescription)"
            )
        }
    }
    
    private func assignConversationToProject(
        conversationID: PersistentIdentifier,
        projectID: PersistentIdentifier?
    ) {
        guard let conversation = queryManager.conversation(with: conversationID) else { return }
        let project = projectID.flatMap { queryManager.project(with: $0) }
        let isShowingConversation = router.activeConversationID == conversation.id
        do {
            try queryManager.assignConversation(conversation, to: project)
            if isShowingConversation {
                router.openConversation(conversation.id, in: project?.id)
            }
        } catch {
            let projectName = project?.name ?? "none"
            vxAtelierPro.log.error(
                "Failed to assign conversation '\(conversation.title)' to project '\(projectName)': \(error.localizedDescription)"
            )
        }
    }
    
    private func requestExportConversation(id: PersistentIdentifier) {
        guard let conversation = queryManager.conversation(with: id) else { return }
        onRequestExportConversation(conversation)
    }
    
    private func deleteBookmarkFromContext(id: PersistentIdentifier) {
        guard let bookmark = queryManager.bookmark(with: id) else { return }
        do {
            try queryManager.delete(bookmark)
            vxAtelierPro.log.debug("Deleted bookmark '\(bookmark.label)' via context menu.")
        } catch {
            vxAtelierPro.log.error(
                "Failed to delete bookmark \(bookmark.label) from context menu: \(error.localizedDescription)"
            )
        }
    }
    
    private func deleteBookmarkFromSwipe(id: PersistentIdentifier) {
        guard let bookmark = queryManager.bookmark(with: id) else { return }
        do {
            try queryManager.delete(bookmark)
            vxAtelierPro.log.debug("Deleted bookmark '\(bookmark.label)' via swipe.")
        } catch {
            vxAtelierPro.log.error(
                "ContentView: Failed during swipe delete for bookmark '\(bookmark.label)': \(error.localizedDescription)"
            )
        }
    }
    
    private func renameBookmark(id: PersistentIdentifier, newTitle: String) {
        guard let bookmark = queryManager.bookmark(with: id) else { return }
        bookmark.label = newTitle
        do {
            try queryManager.saveContext()
        } catch {
            vxAtelierPro.log.error(
                "ContentView: Failed to rename bookmark '\(bookmark.label)': \(error.localizedDescription)"
            )
        }
    }
    
    private func selectBookmark(id: PersistentIdentifier) {
        guard let bookmark = queryManager.bookmark(with: id),
              let conversation = bookmark.turn?.conversation else {
            vxAtelierPro.log.error("Bookmark selection failed: missing conversation.")
            return
        }
        
        if let project = conversation.project {
            router.openConversation(conversation.id, in: project.id)
        } else {
            router.openConversation(conversation.id, in: nil)
        }
    }
    
    private var sidebarActions: ContentSidebarActions {
        ContentSidebarActions(
            deleteProject: deleteProject(id:),
            restoreProject: restoreProject(id:),
            archiveProject: archiveProject(id:),
            renameProject: renameProject(id:newTitle:),
            requestExportProject: requestExportProject(id:),
            deleteConversation: deleteConversation(id:),
            restoreConversation: restoreConversation(id:),
            archiveConversation: archiveConversation(id:),
            renameConversation: renameConversation(id:newTitle:),
            assignConversationToProject: assignConversationToProject(conversationID:projectID:),
            requestExportConversation: requestExportConversation(id:),
            deleteBookmarkFromContext: deleteBookmarkFromContext(id:),
            deleteBookmarkFromSwipe: deleteBookmarkFromSwipe(id:),
            renameBookmark: renameBookmark(id:newTitle:),
            selectBookmark: selectBookmark(id:)
        )
    }
    
    // MARK: - View Components
    private var sidebarView: some View {
        ContentSidebarView(
            contentFilter: contentFilter,
            projects: filteredProjects,
            conversations: standaloneConversations,
            bookmarks: visibleBookmarks,
            selection: Binding(
                get: { router.selection },
                set: { router.setSelection($0) }
            ),
            sidebarProjectsSortDescending: $sidebarProjectsSortDescending,
            sidebarProjectsSortTypeRaw: $sidebarProjectsSortTypeRaw,
            sidebarConversationsSortDescending: $sidebarConversationsSortDescending,
            sidebarConversationsSortTypeRaw: $sidebarConversationsSortTypeRaw,
            showEmptySections: showEmptySections,
            actions: sidebarActions,
            availableProjects: projects.filter { $0.status == .active }
        )
    }
    
    @ViewBuilder
    private func detailView(for selection: SidebarSelection?) -> some View {
        if let selection {
            switch selection {
            case .conversation(let id):
                if let conversation = standaloneConversations.first(where: { $0.id == id }) {
                    ConversationView(
                        conversationID: conversation.id,
                        onRequestOptions: onRequestOptions
                    )
                    .id(conversation.id)
                } else {
                    Text("Item not found.")
                }
            case .project(let id):
                if let project = filteredProjects.first(where: { $0.id == id }) {
                    ProjectView(
                        projectID: project.id,
                        onRequestOptions: onRequestOptions,
                        onDeleteConversation: deleteConversation(id:),
                        onExportProject: requestExportProject(id:)
                    )
                    .id(project.id)
                } else {
                    Text("Item not found.")
                }
            }
        } else {
            detailPlaceholderView
        }
    }
    
    private var detailPlaceholderView: some View {
        DetailPlaceholderView(
            hasAPIConfiguration: queryManager.defaultApiConfiguration != nil,
            onNewConversation: addConversation,
            onNewProject: addProject,
            onConfigureAPI: {
                onRequestSettings(.api)
            },
            onConfigureSettings: {
                onRequestSettings(nil)
            }
        )
    }
    
    // MARK: - Toolbar Menus
    
    /// Menu items for creating new content.
    @ViewBuilder
    private var newItemMenu: some View {
        Button {
            if queryManager.defaultApiConfiguration == nil {
                vxAtelierPro.log.info(
                    "Attempted to create conversation from menu without API configuration")
                return
            }
            if ModifierKeyState.isOptionPressed() {
                addConversationAndOpenOptions()
            } else {
                addConversation()
            }
        } label: {
            MenuItemStyle.label("New Conversation", systemImage: "plus.bubble")
        }
        .help("Create a new conversation. Hold Option to open conversation options.")
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(queryManager.defaultApiConfiguration == nil)
        
        Button {
            if queryManager.defaultApiConfiguration == nil {
                vxAtelierPro.log.info(
                    "Attempted to create project from menu without API configuration")
                return
            }
            addProject()
        } label: {
            MenuItemStyle.label("New Project", systemImage: "folder.badge.plus")
        }
        .help("Create a new project")
        .disabled(queryManager.defaultApiConfiguration == nil)
    }
    
    /// Menu items for importing and exporting data.
    @ViewBuilder
    private var importExportMenu: some View {
        Button {
            onRequestImport()
        } label: {
            MenuItemStyle.label("Import...", systemImage: "arrow.down.doc")
        }
        .help("Import a conversation or project from file")
    }

    /// Menu items for controlling view options.
    @ViewBuilder
    private var viewOptionsMenu: some View {
        Toggle(isOn: $showEmptySections) {
            MenuItemStyle.label("Show Empty Sections", systemImage: "eye")
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .help("Show or hide empty sections in the navigation")
        
        Divider()
        
        Button {
            setContentFilter(.active, contentFilter: $contentFilter)
        } label: {
            MenuItemStyle.label("Show Conversations", systemImage: "tray.full")
        }
        .keyboardShortcut("1", modifiers: [.command])
        .help("Show active conversations")
        
        Button {
            setContentFilter(.archived, contentFilter: $contentFilter)
        } label: {
            MenuItemStyle.label("Show Archive", systemImage: "archivebox")
        }
        .keyboardShortcut("2", modifiers: [.command])
        .help("Show archived items")
        
        Button {
            setContentFilter(.trashed, contentFilter: $contentFilter)
        } label: {
            MenuItemStyle.label("Show Trash", systemImage: "trash")
        }
        .keyboardShortcut("3", modifiers: [.command])
        .help("Show items in trash")
    }
    
    /// Menu items for utility actions like TTS and logs.
    @ViewBuilder
    private var utilityActionsMenu: some View {
        Button {
            onRequestTTS()
        } label: {
            MenuItemStyle.label("Speech Playlist", systemImage: "text.bubble")
        }
        .help("Open text-to-speech queue")
        
        Button {
            onRequestLogHistory()
        } label: {
            MenuItemStyle.label("Log History", systemImage: "list.bullet.clipboard")
        }
        .help("View application log history")
        .keyboardShortcut("l", modifiers: [.command, .option])
    }
    
    /// Menu item for opening application settings.
    @ViewBuilder
    private var settingsMenu: some View {
        Button {
            onRequestSettings(nil)
        } label: {
            MenuItemStyle.label("Application Settings", systemImage: "gear")
        }
        .help("Open application settings")
        .keyboardShortcut(",", modifiers: [.command])
    }
    
    // MARK: - Body
    var body: some View {
        Group {
#if os(iOS)
            if horizontalSizeClass == .compact && !hasVisibleSidebarItems {
                DetailPlaceholderView(
                    hasAPIConfiguration: queryManager.defaultApiConfiguration != nil,
                    onNewConversation: addConversation,
                    onNewProject: addProject,
                    onConfigureAPI: {
                        onRequestSettings(.api)
                    },
                    onConfigureSettings: {
                        onRequestSettings(nil)
                    }
                )
            } else {
                mainContentView
            }
#else
            mainContentView
#endif
        }
        .onChange(of: contentFilter) { _, _ in
            let visibleSelections = filteredProjects.map { SidebarSelection.project($0.id) }
            + standaloneConversations.map { SidebarSelection.conversation($0.id) }
            if let selection = router.selection, !visibleSelections.contains(selection) {
                router.setSelection(nil)
            }
        }
    }
    
    /// Shared main content view for all platforms (except iOS compact/empty placeholder)
    private var mainContentView: some View {
        VStack(spacing: 0) {
#if os(macOS)
            NavigationSplitView {
                sidebarView
                    .toolbar { sidebarToolbar }
            } detail: {
                detailView(for: router.selection)
            }
#else
            NavigationSplitView {
                sidebarView
                    .toolbar { sidebarToolbar }
            } detail: {
                detailView(for: router.selection)
            }
#endif
        }
    }
    
    // MARK: - Toolbar Content
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if contentFilter == .trashed {
                Button(
                    role: .destructive,
                    action: {
                        do {
                            // Store current state before emptying trash
                            let hadTrashedItems =
                            trashedConversationsCount > 0
                            || trashedProjectsCount > 0
                            
                            // Empty trash
                            try queryManager.emptyTrash()
                            
                            // Reset navigation if we had items to empty
                            if hadTrashedItems {
                                setContentFilter(
                                    .active,
                                    contentFilter: $contentFilter,
                                    animated: true
                                )
                                router.setSelection(nil)
                                vxAtelierPro.log.info("Trash emptied, returning to Show Conversations")
                            } else {
                                vxAtelierPro.log.debug(
                                    "Empty trash requested, but trash was already empty")
                            }
                        } catch {
                            vxAtelierPro.log.error(
                                "Failed to empty trash: \(error.localizedDescription)")
                        }
                    }
                ) {
                    Label("Empty Trash", systemImage: "trash.fill")
                }
                .help("Permanently delete all trashed items")
            }
            
            Menu {
                newItemMenu
                Divider()
                importExportMenu
                Divider()
                viewOptionsMenu
                Divider()
                utilityActionsMenu
                Divider()
                settingsMenu
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.gray)
                    .font(.title2)
            }
        }
    }
    
    private func deleteItem(for item: any PersistentModel) {
        let itemId = item.persistentModelID
        let itemType = type(of: item)
        
        clearNavigationIfNeeded(for: item)
        
        do {
            if contentFilter == .trashed {
                try queryManager.deleteItemPermanently(item)
                vxAtelierPro.log.debug(
                    "Successfully initiated permanent deletion for item (ID: \(itemId), Type: \(itemType)) via swipe/delete from trash."
                )
                
                // Only reset navigation if there are NO trashed items remaining (both conversations and projects)
                let remainingTrashedItems = trashedConversationsCount + trashedProjectsCount
                if remainingTrashedItems == 0 {
                    setContentFilter(
                        .active,
                        contentFilter: $contentFilter,
                        animated: true
                    )
                    router.setSelection(nil)
                    vxAtelierPro.log.info("Last trashed item removed, returning to Show Conversations")
                } else {
                    vxAtelierPro.log.debug(
                        "\(remainingTrashedItems) trashed items still remain")
                }
            } else {
                try queryManager.moveItemToTrash(item)
                vxAtelierPro.log.debug(
                    "Successfully moved/deleted item (ID: \(itemId), Type: \(itemType)) via swipe/delete."
                )
            }
        } catch {
            vxAtelierPro.log.error(
                "ContentView: Failed during deleteItem for item (ID: \(itemId), Type: \(itemType)): \(error.localizedDescription)"
            )
        }
    }
    
    private func archiveItem(_ item: any PersistentModel) {
        let itemId = item.persistentModelID
        let itemType = type(of: item)
        let wasInArchive = contentFilter == .archived
        
        do {
            try queryManager.archiveItem(item)
            vxAtelierPro.log.debug("Successfully archived item (ID: \(itemId), Type: \(itemType)).")
            
            if clearNavigationIfNeeded(for: item) {
                
                // If we're in archive view and this was the last item, return to Show Conversations
                if wasInArchive {
                    let remainingArchivedItems = archivedProjectsCount
                    let remainingArchivedConversations = archivedConversationsCount
                    
                    if remainingArchivedItems == 0 && remainingArchivedConversations == 0 {
                        setContentFilter(
                            .active,
                            contentFilter: $contentFilter,
                            animated: true
                        )
                        vxAtelierPro.log.info("Last archived item removed, returning to Show Conversations")
                    }
                }
            }
        } catch {
            vxAtelierPro.log.warning(
                "ContentView: Failed to archive item (ID: \(itemId), Type: \(itemType)): \(error.localizedDescription)"
            )
        }
    }
    
    @discardableResult
    private func clearNavigationIfNeeded(for item: any PersistentModel) -> Bool {
        let itemId = item.persistentModelID
        let itemType = type(of: item)
        
        if let conversation = item as? ConversationItem {
            if router.clearIfShowing(conversationID: conversation.id, projectID: conversation.project?.id) {
                vxAtelierPro.log.debug("Conversation navigation (ID: \(itemId), Type: \(itemType)) cleared.")
                return true
            }
            
            vxAtelierPro.log.debug("Conversation (ID: \(itemId), Type: \(itemType)) was not active; navigation unchanged.")
            return false
        }
        
        if let project = item as? ProjectItem {
            if router.clearIfShowing(projectID: project.id) {
                vxAtelierPro.log.debug("Project navigation (ID: \(itemId), Type: \(itemType)) cleared.")
                return true
            }
            
            vxAtelierPro.log.debug("Project (ID: \(itemId), Type: \(itemType)) was not active; navigation unchanged.")
            return false
        }
        
        vxAtelierPro.log.debug("Item (ID: \(itemId), Type: \(itemType)) was not active; navigation unchanged.")
        return false
    }
    
    private func restoreItem(_ item: any PersistentModel) {
        let itemId = item.persistentModelID
        let itemType = type(of: item)
        do {
            try queryManager.restoreItem(item)
            vxAtelierPro.log.debug("Successfully restored item (ID: \(itemId), Type: \(itemType)).")
        } catch {
            vxAtelierPro.log.warning(
                "ContentView: Failed to restore item (ID: \(itemId), Type: \(itemType)): \(error.localizedDescription)"
            )
        }
    }
    
}

#Preview {
    ContentView(
        onRequestOptions: { _ in },
        onRequestExportProject: { _ in },
        onRequestExportConversation: { _ in },
        onRequestImport: {},
        onRequestSettings: { _ in },
        onRequestTTS: {},
        onRequestLogHistory: {}
    ).bootstrapped(with: .preview())
}
