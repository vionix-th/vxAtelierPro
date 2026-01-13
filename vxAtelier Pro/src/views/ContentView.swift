import SwiftData
import SwiftUI
import Observation

// MARK: - ContentView
struct ContentView: View {
    // MARK: - Environment & Context
    @Environment(\.modelContext) private var modelContext
    @Environment(TTSQueue.self) private var ttsQueue
    @Environment(QueryManager.self) private var queryManager
    @Environment(\.showLogHistory) private var showLogHistory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ConversationViewModelStore.self) private var conversationStore
    @Environment(ViewOptionsStore.self) private var viewOptions

    #if os(macOS)
        private let globalHotkeys = HotkeyManager()
        private let globalUtilityPanel = GlobalUtilityPanel()
    #endif

    // MARK: - State & Bindings
    @State private var selectedItem: PersistentIdentifier?
    @State private var applicationSettingsViewIsPresented: Bool = false
    @State private var ttsViewIsPresented: Bool = false
    @State private var settingsInitialTab: ApplicationSettingsView.SettingsTab? = nil

    // Options sheet hosting (hoisted from ConversationView)
    private struct OptionsSheetKey: Identifiable { let id: PersistentIdentifier }
    @State private var optionsSheetKey: OptionsSheetKey?

    // Task-related state
    @State private var exportProjectRequested: (ProjectItem, UUID)?
    @State private var exportDialogRequested: (ConversationItem, UUID)?
    @State private var importRequested = false

    /// Returns true if there are any visible items in the sidebar (only non-trashed projects and standalone dialogs)
    private var hasVisibleItems: Bool {
        let hasProjects =
            !(viewOptions.showArchived
            ? queryManager.archivedProjects.isEmpty
            : viewOptions.showTrashed
                ? queryManager.trashedProjects.isEmpty : queryManager.activeProjects.isEmpty)
        let hasStandaloneDialogs = viewOptions.showArchived
            ? !queryManager.archivedDialogs.isEmpty
            : viewOptions.showTrashed
                ? !queryManager.trashedDialogs.isEmpty
                : !queryManager.standaloneConversations.isEmpty
        return hasProjects || hasStandaloneDialogs
    }

    // MARK: - Helper Methods

    // MARK: - Actions
    private func addConversation() {
        let conversation = queryManager.createConversation()
        selectedItem = conversation.id
    }

    private func addProject() {
        let project = queryManager.createProject()
        selectedItem = project.id
    }

    private func assignConversationToProject(
        _ conversation: ConversationItem, _ project: ProjectItem?
    ) {
        conversation.project = project
    }


    private func requestOptions(for id: PersistentIdentifier) {
        vxAtelierPro.log.debug("ContentView: options requested for dialog id \(id)")
        optionsSheetKey = OptionsSheetKey(id: id)
    }

    // MARK: - Navigation Links
    func projectNavigationLink(for project: ProjectItem) -> some View {
        NavigationLink {
            ProjectView(
                projectID: project.id,
                onConversationViewAppear: { self.selectedItem = $0.id },
                onRequestOptions: requestOptions
            )
        } label: {
                NavigationItem(
                    title: Binding(get: { project.name }, set: { project.name = $0 }),
                    subtitle: project.timestamp.formatted(
                        .dateTime.year().month().day().hour().minute()),
                    onDelete: {
                        deleteItem(for: project)
                    },
                    onRename: { project.name = $0 },
                    onRestore: project.status != .active
                        ? {
                            restoreItem(project)
                        } : nil,
                    onPermanentDelete: project.status == .trashed
                        ? {
                            deleteItem(for: project)
                        } : nil,
                    onArchive: project.status == .active
                        ? {
                            archiveItem(project)
                        } : nil,
                    imageName: "folder",
                    onProjectAssign: { _ in },
                    onExport: {
                        exportProjectRequested = (project, UUID())
                },
                project: project
            )
        }
    }

    func conversationNavigationLink(for conversation: ConversationItem) -> some View {
        NavigationLink {
            ConversationView(
                viewModel: conversationStore.viewModel(for: conversation.id),
                onRequestOptions: requestOptions
            )
            .id(conversation.id)
        } label: {
            NavigationItem(
                title: Binding(get: { conversation.title }, set: { conversation.title = $0 }),
                subtitle: conversation.timestamp.formatted(
                    .dateTime.year().month().day().hour().minute()),
                onDelete: {
                    deleteItem(for: conversation)
                },
                onRename: { conversation.title = $0 },
                onRestore: conversation.status != .active
                    ? {
                        restoreItem(conversation)
                    } : nil,
                onPermanentDelete: conversation.status == .trashed
                    ? {
                        deleteItem(for: conversation)
                    } : nil,
                onArchive: conversation.status == .active
                    ? {
                        archiveItem(conversation)
                    } : nil,
                imageName: AppDefaults.dialogImageSystemName,
                onProjectAssign: conversation.status == .active
                    ? { project in
                        assignConversationToProject(conversation, project)
                    } : nil,
                onExport: {
                    exportDialogRequested = (conversation, UUID())
                },
                conversation: conversation
            )
        }
    }

    func bookmarkNavigationLink(for bookmark: BookmarkItem) -> some View {
        NavigationLink {
            let conversation = bookmark.turn?.conversation
            if let conversation = conversation {
                ConversationView(
                    viewModel: conversationStore.viewModel(for: conversation.id),
                    scrollHint: queryManager.scrollHint(for: bookmark),
                    onRequestOptions: requestOptions
                )
                .id(conversation.id)
            } else {
                Text("Invalid bookmark: missing conversation.")
            }
        } label: {
            NavigationItem(
                title: Binding(get: { bookmark.label }, set: { bookmark.label = $0 }),
                subtitle: bookmark.turn?.conversation?.title ?? "(missing)",
                onDelete: {
                    do {
                        try queryManager.delete(bookmark)
                        vxAtelierPro.log.debug(
                            "Deleted bookmark '\(bookmark.label)' via context menu.")
                        if selectedItem == bookmark.id {
                            selectedItem = nil
                        }
                    } catch {
                        vxAtelierPro.log.error(
                            "Failed to delete bookmark \(bookmark.label) from context menu: \(error.localizedDescription)"
                        )
                    }
                },
                onRename: {
                    bookmark.label = $0
                },
                imageName: "bookmark"
            )
        }
    }

    // MARK: - View Components
    var sidebarList: some View {        
        return List(selection: $selectedItem) {
            let projectTitle =
                viewOptions.showArchived ? "Archived Projects" : viewOptions.showTrashed ? "Trashed Projects" : "Projects"
            let standaloneDialogTitle =
                viewOptions.showArchived
                ? "Archived Dialogs" : viewOptions.showTrashed ? "Trashed Items" : "Standalone Dialogs"
            let systemDialogTitle = "System"
            let bookmarkTitle = "Bookmarks"

            if !viewOptions.showArchived && !viewOptions.showTrashed {
                dialogSection(title: systemDialogTitle, dialogs: queryManager.systemConversations)
            }

            projectSection(
                title: projectTitle,
                projects: viewOptions.showArchived
                    ? queryManager.archivedProjects
                    : viewOptions.showTrashed ? queryManager.trashedProjects : queryManager.activeProjects
            )

            if viewOptions.showTrashed {
                // Use QueryManager's explicit trashedDialogs property
                let allTrashedDialogs = queryManager.trashedDialogs
                    .sorted(by: { $0.timestamp > $1.timestamp })
                dialogSection(title: standaloneDialogTitle, dialogs: allTrashedDialogs)
            } else {
                dialogSection(
                    title: standaloneDialogTitle, dialogs: queryManager.standaloneConversations)
            }

            if !viewOptions.showArchived && !viewOptions.showTrashed {
                bookmarkSection(title: bookmarkTitle, bookmarks: queryManager.bookmarks)
            }
        }
    }

    /// Builds the detail view based on the selected item ID.
    @ViewBuilder
    private func detailView(for selectedId: PersistentIdentifier?) -> some View {
        if let selectedId = selectedId {
            if let conversation = queryManager.allConversations.first(where: { $0.id == selectedId }
            ) {
                ConversationView(
                    viewModel: conversationStore.viewModel(for: conversation.id),
                    onRequestOptions: requestOptions)
                .id(conversation.id)
            } else if let project = queryManager.allProjects.first(where: { $0.id == selectedId }) {
                ProjectView(
                    projectID: project.id,
                    onConversationViewAppear: { self.selectedItem = $0.id },
                    onRequestOptions: requestOptions
                )
            } else if let bookmark = queryManager.bookmarks.first(where: { $0.id == selectedId }) {
                let conversation = bookmark.turn?.conversation
                if let conversation = conversation {
                    ConversationView(
                        viewModel: conversationStore.viewModel(for: conversation.id),
                        scrollHint: queryManager.scrollHint(for: bookmark),
                        onRequestOptions: requestOptions
                    )
                    .id(conversation.id)
                } else {
                    Text("Invalid bookmark: missing conversation.")
                }
            } else {
                Text("Item not found.")
            }
        } else {
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
        @Bindable var viewOptions = viewOptions
        
        Toggle(isOn: $viewOptions.showEmptySections) {
            MenuItemStyle.label("Show Empty Sections", systemImage: "eye")
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .help("Show or hide empty sections in the navigation")

        Divider()

        Button {
            viewOptions.setNavigationMode(.chats)
        } label: {
            MenuItemStyle.label("Show Chats", systemImage: "tray.full")
        }
            .keyboardShortcut("1", modifiers: [.command])
            .help("Show active chats")

        Button {
            viewOptions.setNavigationMode(.archive)
        } label: {
            MenuItemStyle.label("Show Archive", systemImage: "archivebox")
        }
        .keyboardShortcut("2", modifiers: [.command])
        .help("Show archived items")

        Button {
            viewOptions.setNavigationMode(.trash)
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
        #if os(iOS)
            if horizontalSizeClass == .compact && !hasVisibleItems {
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

    /// Shared main content view for all platforms (except iOS compact/empty placeholder)
    private var mainContentView: some View {
        VStack(spacing: 0) {
            @Bindable var viewOptions = viewOptions
            NavigationSplitView {
                sidebarList
                    .toolbar { sidebarToolbar }
            } detail: {
                detailView(for: selectedItem)
            }

            if viewOptions.statusBarVisible {
                StatusBar(
                    activeItemId: $selectedItem
                )
            }
        }
        .onAppear {
            vxAtelierPro.log.debug("ContentView appearing")
            // Ensure we always start in Show Chats view
            viewOptions.setNavigationMode(.chats, animated: false)
            selectedItem = nil

            registerGlobalHotkeys()
            queryManager.ensureSystemConversation()
            vxAtelierPro.log.info("Application started - Reset to Show Chats view")
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
        .task(id: exportProjectRequested?.1) { await exportTask(for: exportProjectRequested?.0) }
        .task(id: exportDialogRequested?.1) { await exportTask(for: exportDialogRequested?.0) }
        .task(id: importRequested) { await importTask() }
        // Present Settings from the toolbar menu entry
        .sheet(isPresented: $applicationSettingsViewIsPresented, onDismiss: {
            settingsInitialTab = nil
        }) {
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
            if viewOptions.showTrashed {
                Button(
                    role: .destructive,
                    action: {
                        DispatchQueue.main.async {
                            do {
                                // Store current state before emptying trash
                                let hadTrashedItems =
                                    !queryManager.trashedDialogs.isEmpty
                                    || !queryManager.trashedProjects.isEmpty

                        // Empty trash
                        try queryManager.emptyTrash()

                        // Reset navigation if we had items to empty
                        if hadTrashedItems {
                            self.viewOptions.setNavigationMode(.chats, animated: true)
                            self.selectedItem = nil
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
    private func exportTask(for item: (any PersistentModel)?) async {
        guard let item = item else { return }

        do {
            if let project = item as? ProjectItem {
                try await DataManager.shared.exportProject(project)
                vxAtelierPro.log.info("Successfully exported project '\(project.name)'.")
            } else if let conversation = item as? ConversationItem {
                try await DataManager.shared.exportDialog(conversation)
                vxAtelierPro.log.info("Successfully exported conversation '\(conversation.title)'.")
            }
        } catch {
            let itemType = (item is ProjectItem) ? "project" : "dialog"
            vxAtelierPro.log.error("Export \(itemType) failed: \(error.localizedDescription)")
        }
        if item is ProjectItem { exportProjectRequested = nil }
        if item is ConversationItem { exportDialogRequested = nil }
    }

    /// Task to handle importing data.
    private func importTask() async {
        if importRequested {
            defer { importRequested = false }
            do {
                let importedItem = try await DataManager.shared.importData(into: modelContext)
                if let project = importedItem as? ProjectItem {
                    try queryManager.insert(project)
                    selectedItem = project.id
                    vxAtelierPro.log.info("Successfully imported project '\(project.name)'.")
                } else if let dialog = importedItem as? ConversationItem {
                    try queryManager.insert(dialog)
                    selectedItem = dialog.id
                    vxAtelierPro.log.info("Successfully imported dialog '\(dialog.title)'.")
                }
            } catch {
                vxAtelierPro.log.error("Import failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Global Hotkeys (macOS)

    private func registerGlobalHotkeys() {
        #if os(macOS)
            vxAtelierPro.log.debug("Registering global hotkeys")
            globalHotkeys.register(
                key: "k", modifierFlags: [.command],
                action: { _ in
                    vxAtelierPro.log.debug("Global utility panel hotkey triggered")
                    globalHotkeyUtilityPanelAction()
                    return true
                })
        #endif
    }

    private func globalHotkeyUtilityPanelAction() {
        #if os(macOS)
            if let item = queryManager.utilityPanelConversation {
                vxAtelierPro.log.notice("Showing utility panel for existing dialog '\(item.title)'")
                globalUtilityPanel.show(
                    modelContext: modelContext, conversationID: item.id, queryManager: queryManager,
                    didSend: { conversationID in
                        selectedItem = conversationID
                    })
            } else {
                vxAtelierPro.log.notice("Creating new dialog for utility panel")
                let item = queryManager.createConversation()
                item.title = AppDefaults.newDialogName
                if let config = item.options.apiConfiguration {
                    item.options.setupAiRequestArguments(for: config, modelContext: modelContext)
                }
                globalUtilityPanel.show(
                    modelContext: modelContext, conversationID: item.id, queryManager: queryManager,
                    didSend: { conversationID in
                        selectedItem = conversationID
                    })
            }
        #endif
    }

    private func deleteItem(for item: any PersistentModel) {
        let itemId = item.persistentModelID
        let itemType = type(of: item)

        if selectedItem == itemId {
            selectedItem = nil
            vxAtelierPro.log.debug("Selected item (ID: \(itemId), Type: \(itemType)) cleared.")
        } else {
            vxAtelierPro.log.debug("Selected item (ID: \(itemId), Type: \(itemType)) not cleared.")
        }

        DispatchQueue.main.async {
            do {
                if viewOptions.showTrashed {
                    try queryManager.deleteItemPermanently(item)
                    vxAtelierPro.log.debug(
                        "Successfully initiated permanent deletion for item (ID: \(itemId), Type: \(itemType)) via swipe/delete from trash."
                    )

                    // Only reset navigation if there are NO trashed items remaining (both dialogs and projects)
                    let remainingTrashedItems =
                        queryManager.trashedDialogs.count + queryManager.trashedProjects.count
                    if remainingTrashedItems == 0 {
                        self.viewOptions.setNavigationMode(.chats, animated: true)
                        self.selectedItem = nil
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
    }

    private func archiveItem(_ item: any PersistentModel) {
        let itemId = item.persistentModelID
        let itemType = type(of: item)
        let wasInArchive = viewOptions.showArchived

        do {
            try queryManager.archiveItem(item)
            vxAtelierPro.log.debug("Successfully archived item (ID: \(itemId), Type: \(itemType)).")

            if selectedItem == itemId {
                selectedItem = nil

                // If we're in archive view and this was the last item, return to Show Chats
                if wasInArchive {
                    let remainingArchivedItems = queryManager.archivedProjects.count
                    let remainingArchivedDialogs = queryManager.archivedDialogs.count

                    if remainingArchivedItems == 0 && remainingArchivedDialogs == 0 {
                        self.viewOptions.setNavigationMode(.chats, animated: true)
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

    @ViewBuilder
    private func projectSection(title: String, projects: [ProjectItem]) -> some View {
        if !projects.isEmpty || viewOptions.showEmptySections {
            @Bindable var viewOptions = viewOptions
            Section {
                ForEach(
                    queryManager.sortedProjectsForSidebar(
                        projects, descending: viewOptions.sidebarProjectsSortDescending,
                        sortType: SidebarSortType(rawValue: viewOptions.sidebarProjectsSortTypeRaw)
                            ?? .alphabetically)
                ) { project in
                    projectNavigationLink(for: project)
                }
                .onDelete { indexSet in
                    let sorted = queryManager.sortedProjectsForSidebar(
                        projects, descending: viewOptions.sidebarProjectsSortDescending,
                        sortType: SidebarSortType(rawValue: viewOptions.sidebarProjectsSortTypeRaw)
                            ?? .alphabetically)
                    indexSet.forEach { index in
                        if index < sorted.count {
                            let project = sorted[index]
                            deleteItem(for: project)
                        } else {
                            vxAtelierPro.log.warning(
                                "ContentView: Invalid index \(index) encountered in projectSection.onDelete for projects array count \(projects.count)."
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    SidebarSortButton(
                        sortDescending: $viewOptions.sidebarProjectsSortDescending,
                        sortTypeRaw: $viewOptions.sidebarProjectsSortTypeRaw,
                        allowedTypes: [.alphabetically])
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private func dialogSection(title: String, dialogs: [ConversationItem]) -> some View {
        if !dialogs.isEmpty || viewOptions.showEmptySections {
            @Bindable var viewOptions = viewOptions
            Section {
                ForEach(
                    queryManager.sortedConversationsForSidebar(
                        dialogs, descending: viewOptions.sidebarDialogsSortDescending,
                        sortType: SidebarSortType(rawValue: viewOptions.sidebarDialogsSortTypeRaw)
                            ?? .conversationDate)
                ) { dialog in
                    conversationNavigationLink(for: dialog)
                }
                .onDelete { indexSet in
                    let sorted = queryManager.sortedConversationsForSidebar(
                        dialogs, descending: viewOptions.sidebarDialogsSortDescending,
                        sortType: SidebarSortType(rawValue: viewOptions.sidebarDialogsSortTypeRaw)
                            ?? .conversationDate)
                    indexSet.forEach { index in
                        if index < sorted.count {
                            let dialog = sorted[index]
                            deleteItem(for: dialog)
                        } else {
                            vxAtelierPro.log.warning(
                                "ContentView: Invalid index \(index) encountered in dialogSection.onDelete for dialogs array count \(dialogs.count)."
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    SidebarSortButton(
                        sortDescending: $viewOptions.sidebarDialogsSortDescending,
                        sortTypeRaw: $viewOptions.sidebarDialogsSortTypeRaw,
                        allowedTypes: SidebarSortType.allCases)
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private func bookmarkSection(title: String, bookmarks: [BookmarkItem]) -> some View {
        if !bookmarks.isEmpty || viewOptions.showEmptySections {
            Section(title) {
                ForEach(bookmarks) { bookmark in
                    bookmarkNavigationLink(for: bookmark)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        if index < bookmarks.count {
                            let bookmark = bookmarks[index]
                            do {
                                try queryManager.delete(bookmark)
                                vxAtelierPro.log.debug("Deleted bookmark '\(bookmark.label)' via swipe.")
                                if selectedItem == bookmark.id { selectedItem = nil }
                            } catch {
                                vxAtelierPro.log.error(
                                    "ContentView: Failed during swipe delete for bookmark '\(bookmark.label)': \(error.localizedDescription)")
                            }
                        } else {
                            vxAtelierPro.log.warning(
                                "ContentView: Invalid index \(index) encountered in bookmarkSection.onDelete for bookmarks array count \(bookmarks.count).")
                        }
                    }
                }
            }
        }
    }
}
