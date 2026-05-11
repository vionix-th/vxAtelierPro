import Observation
import SwiftData
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Commands

/// Custom commands for the application's main menu
struct AppCommands: Commands {
    @AppStorage(AppSettings.Keys.showEmptySections) private var showEmptySections: Bool = AppDefaults.showEmptySections
    @AppStorage(AppSettings.Keys.contentFilter) private var contentFilter: ContentFilter = .active

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Toggle(
                "Show Empty Sections",
                isOn: $showEmptySections
            )
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button("Show Conversations") {
                setContentFilter(.active, contentFilter: $contentFilter)
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Show Archive") {
                setContentFilter(.archived, contentFilter: $contentFilter)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Show Trash") {
                setContentFilter(.trashed, contentFilter: $contentFilter)
            }
            .keyboardShortcut("3", modifiers: [.command])

            Divider()
        }
    }
}

/// vxAtelier Pro - An AI-powered writing and conversation assistant
///
/// This is the main entry point for the vxAtelier Pro application. It handles the core setup
/// of the application, including the logging system, data model container, and platform-specific UI elements.
@main
struct vxAtelierPro: App {
    // MARK: - Platform-Specific Properties

    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    /// Centralized logging system for the application
    /// Uses LoggingService to route messages to both system logger and status bar
    static let log = LoggingService.shared

    // MARK: - Platform Detection

    #if os(iOS)
        static let iOS: Bool = true
    #else
        static let iOS: Bool = false
    #endif

    #if os(macOS)
        static let macOS: Bool = true
    #else
        static let macOS: Bool = false
    #endif

    // MARK: - Data Management
    enum ProjectMigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            [CurrentSchema.self]
        }

        static var stages: [MigrationStage] = []  // Empty stages = lightweight migration

        enum CurrentSchema: VersionedSchema {
            static var versionIdentifier = Schema.Version(1, 0, 0)
            static var models: [any PersistentModel.Type] {
                [
                    ConversationItem.self,
                    ProjectItem.self,
                    BookmarkItem.self,
                    PromptTemplate.self,
                    VoiceConfigurationItem.self,
                    APIConfigurationItem.self,
                    ModelItem.self,
                    ModelParameterMappingItem.self,
                    ModelParameterAvailabilityItem.self,
                    MessageItem.self,
                    MessageContentPartItem.self,
                    ToolCallItem.self,
                    ResponseRunItem.self,
                    ConversationTurn.self,
                    TurnEvent.self,
                    ConversationOptions.self,
                    WebSearchConfigurationItem.self,
                ]
            }
        }
    }

    /// Shared SwiftData container for managing persistent data
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            APIConfigurationItem.self,
            ModelItem.self,
            ModelParameterMappingItem.self,
            ModelParameterAvailabilityItem.self,
            ConversationOptions.self,
            MessageItem.self,
            MessageContentPartItem.self,
            ToolCallItem.self,
            ResponseRunItem.self,
            ConversationTurn.self,
            TurnEvent.self,
            ConversationItem.self,
            ProjectItem.self,
            BookmarkItem.self,
            PromptTemplate.self,
            VoiceConfigurationItem.self,
            WebSearchConfigurationItem.self,
        ])
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isRunningTests)

        do {
            return try ModelContainer(
                for: schema, migrationPlan: ProjectMigrationPlan.self,
                configurations: modelConfiguration)
        } catch {
            vxAtelierPro.log.error("Failed to create ModelContainer: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private let queryManager: QueryManager
    private let ttsQueue: TTSQueue
    private let conversationStore: ConversationViewModelStore
    private let appSceneModel: AppSceneModel
    #if os(macOS)
        private let hotkeyController: GlobalHotkeyController
    #endif

    @AppStorage(AppSettings.Keys.appearanceStyle) private var appearanceStyle: AppearanceStyle = .system

    private var effectiveColorScheme: ColorScheme? {
        switch appearanceStyle {
        case .system:
            return nil  // Follow system, do not override
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    init() {
        vxAtelierPro.log.debug("Initializing vxAtelierPro")

        vxAtelierPro.log.debug("Initializing Query Manager")
        self.queryManager = QueryManager(modelContext: sharedModelContainer.mainContext)
        vxAtelierPro.log.debug("Query Manager initialized")

        vxAtelierPro.log.debug("Initializing TTS Queue")
        self.ttsQueue = TTSQueue(modelContext: sharedModelContainer.mainContext)
        vxAtelierPro.log.debug("TTS Queue initialized")

        vxAtelierPro.log.debug("Initializing Conversation ViewModel Store")
        self.conversationStore = ConversationViewModelStore(
            queryManager: queryManager, ttsQueue: ttsQueue)
        vxAtelierPro.log.debug("Conversation ViewModel Store initialized")

        vxAtelierPro.log.debug("Initializing App Scene Model")
        self.appSceneModel = AppSceneModel(
            queryManager: queryManager,
            modelContext: sharedModelContainer.mainContext
        )
        vxAtelierPro.log.debug("App Scene Model initialized")

        #if os(macOS)
            vxAtelierPro.log.debug("Initializing Global Hotkey Controller")
            self.hotkeyController = GlobalHotkeyController(appSceneModel: appSceneModel)
            appDelegate.onDidFinishLaunching = {
                [hotkeyController] in
                Task { @MainActor in
                    hotkeyController.register()
                }
            }

            vxAtelierPro.log.debug("Global Hotkey Controller initialized")
        #endif

        vxAtelierPro.log.debug("Ensuring system conversation")
        queryManager.ensureSystemConversation()
        vxAtelierPro.log.debug("System conversation ensured")

        vxAtelierPro.log.debug("Registering Tools")
        registerDefaultTools()
        vxAtelierPro.log.debug("Tools registered")

        #if os(macOS)
            if UserDefaults.standard.bool(forKey: AppSettings.Keys.makeKeyAndOrderFront) {
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    vxAtelierPro.log.debug("Brought app to front on startup")
                }
            }
        #endif

        vxAtelierPro.log.debug("vxAtelierPro initialized")
    }

    // MARK: - Tool Registration
    private func registerDefaultTools() {
        let registry = LLMToolRegistry.shared
        let context = sharedModelContainer.mainContext

        // Conversation Tools
        registry.registerTool(ListConversationsTool(modelContext: context))
        registry.registerTool(RenameConversationTool(modelContext: context))
        registry.registerTool(FindConversationTool(modelContext: context))
        registry.registerTool(CurrentConversationTool())

        // Shortcut Tools
        #if os(macOS)
            registry.registerTool(ListShortcutsTool())
            registry.registerTool(RunShortcutTool())
        #endif

        // Settings Tools
        registry.registerTool(ListSettingsTool())
        registry.registerTool(ReadSettingTool())
        registry.registerTool(WriteSettingTool())

        // Web Search Tool (New) - Pass QueryManager
        registry.registerTool(WebSearchTool(queryManager: queryManager))

        // Website Reader Tool
        registry.registerTool(ReadWebsiteTool())
    }

    // MARK: - Scene Configuration

    var body: some Scene {
        WindowGroup("Main Window", id: "mainWindow") {
            AppShellView()
                .preferredColorScheme(effectiveColorScheme)
                .environment(conversationStore)
                .environment(appSceneModel)
        }
        .modelContainer(sharedModelContainer)
        .environment(queryManager)
        .environment(ttsQueue)
        .commands {
            AppCommands()
        }

        #if os(macOS)
            Window("Utility", id: "utilityPanel") {
                UtilityPanelView()
                    .preferredColorScheme(effectiveColorScheme)
                    .environment(queryManager)
                    .environment(appSceneModel)
                    .environment(ttsQueue)
                    .modelContainer(sharedModelContainer)
            }
            .windowResizability(.contentSize)
            .defaultSize(width: 420, height: 140)

            MenuBarExtra("vxAtelier Pro", systemImage: "message.circle") {
                MenuBarContent()
            }
        #endif
    }
}

// MARK: - Platform-Specific Components

#if os(macOS)
    /// Menu bar extra content for macOS
    struct MenuBarContent: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Button("New Window") {
                openWindow(id: "mainWindow")
                vxAtelierPro.log.info("Opened new window from menu bar")
            }

            Divider()

            Button("Quit vxAtelier Pro") {
                vxAtelierPro.log.notice("Application quit requested from menu bar")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    @MainActor
    final class GlobalHotkeyController {
        private let hotkeys = HotkeyManager()
        private let appSceneModel: AppSceneModel
        private var didRegister = false

        init(appSceneModel: AppSceneModel) {
            self.appSceneModel = appSceneModel
        }

        func register() {
            guard !didRegister else { return }
            didRegister = true
            vxAtelierPro.log.debug("Registering global hotkeys")
            hotkeys.register(
                key: "k",
                modifierFlags: [.command],
                action: { [weak self] _ in
                    guard let self else { return false }
                    vxAtelierPro.log.debug("Global utility panel hotkey triggered")
                    Task { @MainActor in
                        self.appSceneModel.requestUtilityPanel()
                    }
                    return true
                }
            )
        }
    }

    /// Application delegate for macOS-specific behaviors
    class AppDelegate: NSObject, NSApplicationDelegate {
        var onDidFinishLaunching: (() -> Void)?

        func applicationDidFinishLaunching(_ notification: Notification) {
            vxAtelierPro.log.debug("Application did finish launching")
            onDidFinishLaunching?()
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            let shouldTerminate = UserDefaults.standard.bool(
                forKey: AppSettings.Keys.shouldTerminateAfterLastWindowClosed)
            vxAtelierPro.log.debug(
                "Checking if should terminate after last window closed: \(shouldTerminate)")
            return shouldTerminate
        }
    }
#endif

// MARK: - View Extensions

extension View {
    /// Hides the keyboard on iOS devices
    func hideKeyboard() {
        #if os(iOS)
            vxAtelierPro.log.debug("Hiding keyboard")
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
