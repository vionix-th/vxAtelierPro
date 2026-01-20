import SwiftData
import SwiftUI

// MARK: - ContentView
struct ContentView: View {
    // MARK: - Environment & Context
    @Environment(QueryManager.self) private var queryManager
    @Environment(NavigationRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ConversationViewModelStore.self) private var conversationStore

    @Query(sort: [SortDescriptor(\ProjectItem.name)]) private var projects: [ProjectItem]
    @Query(sort: [SortDescriptor(\ConversationItem.timestamp, order: .reverse)]) private var conversations: [ConversationItem]
    @Query(sort: [SortDescriptor(\BookmarkItem.label)]) private var bookmarks: [BookmarkItem]

    // MARK: - View Options (UserDefaults-backed)
    @AppStorage(AppSettings.Keys.showEmptySections) private var showEmptySections: Bool = AppDefaults.showEmptySections
    @AppStorage(AppSettings.Keys.showSystemDialogs) private var showSystemDialogs: Bool = AppDefaults.showSystemDialogs
    @AppStorage(AppSettings.Keys.navigationMode) private var navigationMode: NavigationMode = .chats
    @AppStorage(AppSettings.Keys.sidebarDialogsSortDescending) private var sidebarDialogsSortDescending: Bool = true
    @AppStorage(AppSettings.Keys.sidebarDialogsSortType) private var sidebarDialogsSortTypeRaw: String =
        SidebarSortType.conversationDate.rawValue
    @AppStorage(AppSettings.Keys.sidebarProjectsSortDescending) private var sidebarProjectsSortDescending: Bool = false
    @AppStorage(AppSettings.Keys.sidebarProjectsSortType) private var sidebarProjectsSortTypeRaw: String =
        SidebarSortType.alphabetically.rawValue

    // MARK: - State & Bindings
    let onRequestOptions: (PersistentIdentifier) -> Void
    let onRequestExportProject: (ProjectItem) -> Void
    let onRequestExportConversation: (ConversationItem) -> Void
    let onRequestImport: () -> Void
    let onRequestSettings: (ApplicationSettingsView.SettingsTab?) -> Void
    let onRequestTTS: () -> Void
    let onRequestLogHistory: () -> Void

    private var filteredProjects: [ProjectItem] {
        switch navigationMode {
        case .chats:
            return projects.filter { $0.status == .active }
        case .archive:
            return projects.filter { $0.status == .archived }
        case .trash:
            return projects.filter { $0.status == .trashed }
        }
    }

    private var standaloneDialogs: [ConversationItem] {
        conversations.filter { conversation in
            guard conversation.project == nil else { return false }
            switch navigationMode {
            case .chats:
                if conversation.status != .active { return false }
            case .archive:
                if conversation.status != .archived { return false }
            case .trash:
                if conversation.status != .trashed { return false }
            }
            if !showSystemDialogs && conversation.purpose == .system {
                return false
            }
            return true
        }
    }

    private var visibleBookmarks: [BookmarkItem] {
        navigationMode == .chats ? bookmarks : []
    }
    
    private var hasVisibleSidebarItems: Bool {
        !filteredProjects.isEmpty || !standaloneDialogs.isEmpty || !visibleBookmarks.isEmpty
    }
    
    private var trashedDialogsCount: Int {
        conversations.filter { $0.status == .trashed && $0.project == nil }.count
    }
    
    private var trashedProjectsCount: Int {
        projects.filter { $0.status == .trashed }.count
    }
    
    private var archivedDialogsCount: Int {
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

    private func addProject() {
        do {
            let project = try queryManager.createProject()
            router.setSelection(.project(project.id))
        } catch {
            vxAtelierPro.log.error("Failed to create project: \(error.localizedDescription)")
        }
    }

    private func assignConversationToProject(
        _ conversation: ConversationItem, _ project: ProjectItem?
    ) {
        do {
            try queryManager.assignConversation(conversation, to: project)
        } catch {
            let projectName = project?.name ?? "none"
            vxAtelierPro.log.error(
                "Failed to assign conversation '\(conversation.title)' to project '\(projectName)': \(error.localizedDescription)"
            )
        }
    }

    private func initialConversationID(for projectID: PersistentIdentifier) -> PersistentIdentifier? {
        if case .conversation(let id)? = router.path(for: projectID).last {
            return id
        }
        return nil
    }

    private func selectConversationFromBookmark(_ bookmark: BookmarkItem) {
        guard let conversation = bookmark.turn?.conversation else {
            vxAtelierPro.log.error("Bookmark selection failed: missing conversation.")
            return
        }

        if let project = conversation.project {
            router.openConversation(conversation.id, in: project.id)
        } else {
            router.openConversation(conversation.id, in: nil)
        }
    }

    private func deleteBookmarkFromContext(_ bookmark: BookmarkItem) {
        do {
            try queryManager.delete(bookmark)
            vxAtelierPro.log.debug(
                "Deleted bookmark '\(bookmark.label)' via context menu.")
        } catch {
            vxAtelierPro.log.error(
                "Failed to delete bookmark \(bookmark.label) from context menu: \(error.localizedDescription)"
            )
        }
    }

    private func deleteBookmarkFromSwipe(_ bookmark: BookmarkItem) {
        do {
            try queryManager.delete(bookmark)
            vxAtelierPro.log.debug(
                "Deleted bookmark '\(bookmark.label)' via swipe.")
        } catch {
            vxAtelierPro.log.error(
                "ContentView: Failed during swipe delete for bookmark '\(bookmark.label)': \(error.localizedDescription)"
            )
        }
    }

    private var sidebarActions: ContentSidebarActions {
        ContentSidebarActions(
            deleteItem: { deleteItem(for: $0) },
            restoreItem: { restoreItem($0) },
            archiveItem: { archiveItem($0) },
            assignConversationToProject: { conversation, project in
                assignConversationToProject(conversation, project)
            },
            requestExportProject: { project in
                onRequestExportProject(project)
            },
            requestExportConversation: { conversation in
                onRequestExportConversation(conversation)
            },
            deleteBookmarkFromContext: { bookmark in
                deleteBookmarkFromContext(bookmark)
            },
            deleteBookmarkFromSwipe: { bookmark in
                deleteBookmarkFromSwipe(bookmark)
            },
            selectBookmark: { bookmark in
                selectConversationFromBookmark(bookmark)
            }
        )
    }

    // MARK: - View Components
    private var sidebarView: some View {
        ContentSidebarView(
            navigationMode: navigationMode,
            projects: filteredProjects,
            dialogs: standaloneDialogs,
            bookmarks: visibleBookmarks,
            selection: Binding(
                get: { router.selection },
                set: { router.setSelection($0) }
            ),
            sidebarProjectsSortDescending: $sidebarProjectsSortDescending,
            sidebarProjectsSortTypeRaw: $sidebarProjectsSortTypeRaw,
            sidebarDialogsSortDescending: $sidebarDialogsSortDescending,
            sidebarDialogsSortTypeRaw: $sidebarDialogsSortTypeRaw,
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
                if let conversation = standaloneDialogs.first(where: { $0.id == id }) {
                    ConversationView(
                        viewModel: conversationStore.viewModel(for: conversation.id),
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
                        initialConversationID: initialConversationID(for: project.id),
                        onRequestOptions: onRequestOptions,
                        onDeleteConversation: { conversation in
                            deleteItem(for: conversation)
                        },
                        onExportProject: { project in
                            onRequestExportProject(project)
                        }
                    )
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
            onNewDialog: addConversation,
            onNewProject: addProject,
            onConfigureAPI: {
                onRequestSettings(.api)
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
                    "Attempted to create dialog from menu without API configuration")
                return
            }
            addConversation()
        } label: {
            MenuItemStyle.label("New Dialog", systemImage: "plus.bubble")
        }
        .help("Create a new dialog")
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
        .help("Import a dialog or project from file")
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
            setNavigationMode(.chats, navigationMode: $navigationMode)
        } label: {
            MenuItemStyle.label("Show Chats", systemImage: "tray.full")
        }
        .keyboardShortcut("1", modifiers: [.command])
        .help("Show active chats")

        Button {
            setNavigationMode(.archive, navigationMode: $navigationMode)
        } label: {
            MenuItemStyle.label("Show Archive", systemImage: "archivebox")
        }
        .keyboardShortcut("2", modifiers: [.command])
        .help("Show archived items")

        Button {
            setNavigationMode(.trash, navigationMode: $navigationMode)
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
                        onNewDialog: addConversation,
                        onNewProject: addProject,
                        onConfigureAPI: {
                            onRequestSettings(.api)
                        }
                    )
                } else {
                    mainContentView
                }
            #else
                mainContentView
            #endif
        }
        .onChange(of: navigationMode) { _, _ in
            let visibleSelections = filteredProjects.map { SidebarSelection.project($0.id) }
                + standaloneDialogs.map { SidebarSelection.conversation($0.id) }
            if let selection = router.selection, !visibleSelections.contains(selection) {
                router.setSelection(nil)
            }
        }
        .onChange(of: conversations) { _, updated in
            let ids = Set(updated.map(\.id))
            conversationStore.prune(toExisting: ids)
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
                    detailPlaceholderView
                }
                .navigationDestination(for: SidebarSelection.self) { selection in
                    detailView(for: selection)
                }
            #endif

        }
        .onReceive(NotificationCenter.default.publisher(for: .utilityPanelDidSendConversation)) {
            notification in
            if let conversationID = notification.object as? PersistentIdentifier {
                router.openConversation(conversationID, in: nil)
            }
        }
    }

    // MARK: - Toolbar Content
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if navigationMode == .trash {
                Button(
                    role: .destructive,
                    action: {
                        do {
                            // Store current state before emptying trash
                            let hadTrashedItems =
                                trashedDialogsCount > 0
                                || trashedProjectsCount > 0

                            // Empty trash
                            try queryManager.emptyTrash()

                            // Reset navigation if we had items to empty
                            if hadTrashedItems {
                                setNavigationMode(
                                    .chats,
                                    navigationMode: $navigationMode,
                                    animated: true
                                )
                                router.setSelection(nil)
                                vxAtelierPro.log.info("Trash emptied, returning to Show Chats")
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
        if let conversation = item as? ConversationItem {
            conversationStore.remove(conversation.id)
        }

        if selectionMatches(router.selection, item: item) {
            router.setSelection(nil)
            vxAtelierPro.log.debug("Selected item (ID: \(itemId), Type: \(itemType)) cleared.")
        } else {
            vxAtelierPro.log.debug("Selected item (ID: \(itemId), Type: \(itemType)) not cleared.")
        }

        do {
            if navigationMode == .trash {
                try queryManager.deleteItemPermanently(item)
                vxAtelierPro.log.debug(
                    "Successfully initiated permanent deletion for item (ID: \(itemId), Type: \(itemType)) via swipe/delete from trash."
                )

                // Only reset navigation if there are NO trashed items remaining (both dialogs and projects)
                let remainingTrashedItems = trashedDialogsCount + trashedProjectsCount
                if remainingTrashedItems == 0 {
                    setNavigationMode(
                        .chats,
                        navigationMode: $navigationMode,
                        animated: true
                    )
                    router.setSelection(nil)
                    vxAtelierPro.log.info("Last trashed item removed, returning to Show Chats")
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
        let wasInArchive = navigationMode == .archive

        do {
            try queryManager.archiveItem(item)
            vxAtelierPro.log.debug("Successfully archived item (ID: \(itemId), Type: \(itemType)).")

            if selectionMatches(router.selection, item: item) {
                router.setSelection(nil)

                // If we're in archive view and this was the last item, return to Show Chats
                if wasInArchive {
                    let remainingArchivedItems = archivedProjectsCount
                    let remainingArchivedDialogs = archivedDialogsCount

                    if remainingArchivedItems == 0 && remainingArchivedDialogs == 0 {
                        setNavigationMode(
                            .chats,
                            navigationMode: $navigationMode,
                            animated: true
                        )
                        vxAtelierPro.log.info("Last archived item removed, returning to Show Chats")
                    }
                }
            }
        } catch {
            vxAtelierPro.log.warning(
                "ContentView: Failed to archive item (ID: \(itemId), Type: \(itemType)): \(error.localizedDescription)"
            )
        }
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
