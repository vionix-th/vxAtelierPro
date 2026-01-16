import SwiftData
import SwiftUI

// MARK: - ContentView
struct ContentView: View {
    // MARK: - Environment & Context
    @Environment(\.modelContext) private var modelContext
    @Environment(TTSQueue.self) private var ttsQueue
    @Environment(QueryManager.self) private var queryManager
    @Environment(\.showLogHistory) private var showLogHistory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ConversationViewModelStore.self) private var conversationStore

    // MARK: - View Options (UserDefaults-backed)
    @AppStorage("ShowEmptySections") private var showEmptySections: Bool = AppDefaults.showEmptySections
    @AppStorage("ShowSystemDialogs") private var showSystemDialogs: Bool = AppDefaults.showSystemDialogs
    @AppStorage("NavigationMode") private var navigationMode: NavigationMode = .chats
    @AppStorage("statusBarVisible") private var statusBarVisible: Bool = AppDefaults.statusBarVisible
    @AppStorage("SidebarDialogsSortOrderDescending") private var sidebarDialogsSortDescending: Bool = true
    @AppStorage("SidebarDialogsSortType") private var sidebarDialogsSortTypeRaw: String =
        SidebarSortType.conversationDate.rawValue
    @AppStorage("SidebarProjectsSortOrderDescending") private var sidebarProjectsSortDescending: Bool = false
    @AppStorage("SidebarProjectsSortType") private var sidebarProjectsSortTypeRaw: String =
        SidebarSortType.alphabetically.rawValue

    // MARK: - State & Bindings
    @State private var selection: SidebarSelection?
    @State private var applicationSettingsViewIsPresented: Bool = false
    @State private var ttsViewIsPresented: Bool = false
    @State private var settingsInitialTab: ApplicationSettingsView.SettingsTab? = nil
    @State private var activeConversationID: PersistentIdentifier?
    @State private var pendingProjectConversationSelection: ProjectConversationSelection?

    // Options sheet hosting (hoisted from ConversationView)
    private struct OptionsSheetKey: Identifiable { let id: PersistentIdentifier }
    @State private var optionsSheetKey: OptionsSheetKey?

    // Task-related state
    private enum ExportRequest: Identifiable {
        case project(ProjectItem, UUID)
        case conversation(ConversationItem, UUID)

        var id: UUID {
            switch self {
            case .project(_, let id):
                return id
            case .conversation(_, let id):
                return id
            }
        }
    }

    @State private var exportRequest: ExportRequest?
    @State private var importRequested = false

    private var sidebarDataSource: ContentSidebarDataSource {
        ContentSidebarDataSource(
            queryManager: queryManager,
            navigationMode: navigationMode,
            showSystemDialogs: showSystemDialogs
        )
    }

    // MARK: - Helper Methods
    // MARK: - Actions
    private func addConversation() {
        let conversation = queryManager.createConversation()
        selection = .conversation(conversation.id)
    }

    private func addProject() {
        let project = queryManager.createProject()
        selection = .project(project.id)
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

    private func requestOptions(for id: PersistentIdentifier) {
        vxAtelierPro.log.debug("ContentView: options requested for dialog id \(id)")
        optionsSheetKey = OptionsSheetKey(id: id)
    }

    private func requestExport(project: ProjectItem) {
        exportRequest = .project(project, UUID())
    }

    private func requestExport(conversation: ConversationItem) {
        exportRequest = .conversation(conversation, UUID())
    }

    private var activeConversationBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { activeConversationID },
            set: { _ in }
        )
    }

    private func projectConversationSelectionBinding(
        for projectID: PersistentIdentifier
    ) -> Binding<PersistentIdentifier?> {
        Binding(
            get: {
                guard let pending = pendingProjectConversationSelection,
                      pending.projectID == projectID else { return nil }
                return pending.conversationID
            },
            set: { newValue in
                if let newValue {
                    pendingProjectConversationSelection = ProjectConversationSelection(
                        projectID: projectID,
                        conversationID: newValue
                    )
                } else if pendingProjectConversationSelection?.projectID == projectID {
                    pendingProjectConversationSelection = nil
                }
            }
        )
    }

    private func selectConversationFromBookmark(_ bookmark: BookmarkItem) {
        guard let conversation = bookmark.turn?.conversation else {
            vxAtelierPro.log.error("Bookmark selection failed: missing conversation.")
            return
        }

        if let project = conversation.project {
            selection = .project(project.id)
            pendingProjectConversationSelection = ProjectConversationSelection(
                projectID: project.id,
                conversationID: conversation.id
            )
        } else {
            selection = .conversation(conversation.id)
            pendingProjectConversationSelection = nil
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
                requestExport(project: project)
            },
            requestExportConversation: { conversation in
                requestExport(conversation: conversation)
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
            dataSource: sidebarDataSource,
            selection: $selection,
            sidebarProjectsSortDescending: $sidebarProjectsSortDescending,
            sidebarProjectsSortTypeRaw: $sidebarProjectsSortTypeRaw,
            sidebarDialogsSortDescending: $sidebarDialogsSortDescending,
            sidebarDialogsSortTypeRaw: $sidebarDialogsSortTypeRaw,
            showEmptySections: showEmptySections,
            actions: sidebarActions
        )
    }

    @ViewBuilder
    private func detailView(for selection: SidebarSelection?) -> some View {
        if let selection {
            switch selection {
            case .conversation(let id):
                if let conversation = queryManager.allConversations.first(where: { $0.id == id }) {
                    ConversationView(
                        viewModel: conversationStore.viewModel(for: conversation.id),
                        onRequestOptions: requestOptions
                    )
                    .id(conversation.id)
                } else {
                    Text("Item not found.")
                }
            case .project(let id):
                if let project = queryManager.allProjects.first(where: { $0.id == id }) {
                    ProjectView(
                        projectID: project.id,
                        selectedConversationID: projectConversationSelectionBinding(for: project.id),
                        onActiveConversationChange: { activeConversationID = $0 },
                        onRequestOptions: requestOptions,
                        onDeleteConversation: { conversation in
                            deleteItem(for: conversation)
                        },
                        onExportProject: { project in
                            requestExport(project: project)
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
                settingsInitialTab = .api
                applicationSettingsViewIsPresented = true
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
            importRequested = true
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
            ttsViewIsPresented = true
        } label: {
            MenuItemStyle.label("Speech Playlist", systemImage: "text.bubble")
        }
        .help("Open text-to-speech queue")

        Button {
            showLogHistory()
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
            settingsInitialTab = nil
            applicationSettingsViewIsPresented = true
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
                if horizontalSizeClass == .compact && !sidebarDataSource.hasVisibleItems {
                    DetailPlaceholderView(
                        hasAPIConfiguration: queryManager.defaultApiConfiguration != nil,
                        onNewDialog: addConversation,
                        onNewProject: addProject,
                        onConfigureAPI: {
                            settingsInitialTab = .api
                            applicationSettingsViewIsPresented = true
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
            let visibleSelections = sidebarDataSource.visibleSelections
            if let selection, !visibleSelections.contains(selection) {
                self.selection = nil
            }
        }
        .onChange(of: selection) { _, newValue in
            activeConversationID = newValue?.conversationID
            if case .conversation = newValue {
                pendingProjectConversationSelection = nil
            } else if case .project(let projectID) = newValue,
                      pendingProjectConversationSelection?.projectID != projectID {
                pendingProjectConversationSelection = nil
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
                    detailView(for: selection)
                }
            #else
                NavigationSplitView {
                    sidebarView
                        .toolbar { sidebarToolbar }
                } detail: {
                    detailPlaceholderView
                }
                .navigationDestination(for: SidebarSelection.self) { selection in
                    switch selection {
                    case .conversation(let id):
                        if let conversation = queryManager.allConversations.first(where: { $0.id == id }) {
                            ConversationView(
                                viewModel: conversationStore.viewModel(for: conversation.id),
                                onRequestOptions: requestOptions
                            )
                            .id(conversation.id)
                        } else {
                            Text("Item not found.")
                        }
                    case .project(let id):
                        if let project = queryManager.allProjects.first(where: { $0.id == id }) {
                            ProjectView(
                                projectID: project.id,
                                selectedConversationID: projectConversationSelectionBinding(for: project.id),
                                onActiveConversationChange: { activeConversationID = $0 },
                                onRequestOptions: requestOptions,
                                onDeleteConversation: { conversation in
                                    deleteItem(for: conversation)
                                },
                                onExportProject: { project in
                                    requestExport(project: project)
                                }
                            )
                        } else {
                            Text("Item not found.")
                        }
                    }
                }
            #endif

            if statusBarVisible {
                StatusBar(
                    activeItemId: activeConversationBinding
                )
            }
        }
        #if os(iOS)
            .onChange(of: ttsQueue.isPlaying) {
                if ttsQueue.isPlaying {
                    vxAtelierPro.log.info("TTS playback started")
                    ttsViewIsPresented = true
                }
            }
        #else
            .onChange(of: ttsQueue.isPlaying) { _, _ in
                if ttsQueue.isPlaying {
                    vxAtelierPro.log.info("TTS playback started")
                    ttsViewIsPresented = true
                }
            }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .utilityPanelDidSendConversation)) {
            notification in
            if let conversationID = notification.object as? PersistentIdentifier {
                selection = .conversation(conversationID)
                pendingProjectConversationSelection = nil
            }
        }
        .task(id: exportRequest?.id) { await exportTask(for: exportRequest) }
        .task(id: importRequested) { await importTask() }
        // Present Settings from the toolbar menu entry
        .sheet(
            isPresented: $applicationSettingsViewIsPresented,
            onDismiss: {
                settingsInitialTab = nil
            }
        ) {
            ApplicationSettingsView(initialTab: settingsInitialTab)
                .environment(queryManager)
                .environment(\.modelContext, modelContext)
                #if os(macOS)
                    .frame(idealWidth: 900, idealHeight: 640)
                #else
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                #endif
        }
        // Hoisted dialog options sheet (stable parent anchor)
        .sheet(
            item: $optionsSheetKey,
            onDismiss: {
                vxAtelierPro.log.debug("ContentView: options sheet dismissed (onDismiss)")
            }
        ) { key in
            if let dialog = queryManager.allConversations.first(where: { $0.id == key.id }) {
                ConversationOptionsView(
                    options: Binding(get: { dialog.options }, set: { dialog.options = $0 })
                )
                .onAppear {
                    vxAtelierPro.log.debug(
                        "ContentView: options sheet presented for dialog '\(dialog.title)' (id: \(dialog.id))"
                    )
                }
                .onDisappear {
                    do {
                        try queryManager.saveContext()
                        vxAtelierPro.log.debug(
                            "ContentView: Saved context after options dismissed for dialog '\(dialog.title)'."
                        )
                    } catch {
                        vxAtelierPro.log.error(
                            "ContentView: Failed to save context after options dismissed: \(error.localizedDescription)"
                        )
                    }
                }
            } else {
                VStack(spacing: AppDefaults.paddingMedium) {
                    ProgressView()
                    Text("Preparing options…")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 300, minHeight: 200)
                .onAppear {
                    vxAtelierPro.log.debug(
                        "ContentView: options sheet waiting for conversation to resolve (requested id: \(key.id))"
                    )
                }
            }
        }
        // TTS playlist sheet
        .sheet(isPresented: $ttsViewIsPresented) {
            TTSControlView()
                .onAppear { vxAtelierPro.log.debug("ContentView: TTSControlView presented") }
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
                                !queryManager.trashedDialogs.isEmpty
                                || !queryManager.trashedProjects.isEmpty

                            // Empty trash
                            try queryManager.emptyTrash()

                            // Reset navigation if we had items to empty
                            if hadTrashedItems {
                                setNavigationMode(
                                    .chats,
                                    navigationMode: $navigationMode,
                                    animated: true
                                )
                                self.selection = nil
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

    // MARK: - Async Tasks

    /// Generic export task for Projects or Dialogs.
    @MainActor
    private func exportTask(for request: ExportRequest?) async {
        guard let request = request else { return }

        do {
            switch request {
            case .project(let project, _):
                try await DataManager.shared.exportProject(project)
                vxAtelierPro.log.info("Successfully exported project '\(project.name)'.")
            case .conversation(let conversation, _):
                try await DataManager.shared.exportDialog(conversation)
                vxAtelierPro.log.info("Successfully exported conversation '\(conversation.title)'.")
            }
        } catch {
            let itemType: String
            switch request {
            case .project:
                itemType = "project"
            case .conversation:
                itemType = "dialog"
            }
            vxAtelierPro.log.error("Export \(itemType) failed: \(error.localizedDescription)")
        }
        exportRequest = nil
    }

    /// Task to handle importing data.
    @MainActor
    private func importTask() async {
        if importRequested {
            defer { importRequested = false }
            do {
                let importedItem = try await DataManager.shared.importData(into: modelContext)
                if let project = importedItem as? ProjectItem {
                    try queryManager.insert(project)
                    selection = .project(project.id)
                    vxAtelierPro.log.info("Successfully imported project '\(project.name)'.")
                } else if let dialog = importedItem as? ConversationItem {
                    try queryManager.insert(dialog)
                    selection = .conversation(dialog.id)
                    vxAtelierPro.log.info("Successfully imported dialog '\(dialog.title)'.")
                }
            } catch {
                vxAtelierPro.log.error("Import failed: \(error.localizedDescription)")
            }
        }
    }

    private func deleteItem(for item: any PersistentModel) {
        let itemId = item.persistentModelID
        let itemType = type(of: item)

        if selectionMatches(selection, item: item) {
            selection = nil
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
                let remainingTrashedItems =
                    queryManager.trashedDialogs.count + queryManager.trashedProjects.count
                if remainingTrashedItems == 0 {
                    setNavigationMode(
                        .chats,
                        navigationMode: $navigationMode,
                        animated: true
                    )
                    self.selection = nil
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

            if selectionMatches(selection, item: item) {
                selection = nil

                // If we're in archive view and this was the last item, return to Show Chats
                if wasInArchive {
                    let remainingArchivedItems = queryManager.archivedProjects.count
                    let remainingArchivedDialogs = queryManager.archivedDialogs.count

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
