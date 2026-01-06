import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

// MARK: - Commands

/// Custom commands for the application's main menu
struct AppCommands: Commands {
    @AppStorage("ShowEmptySections") private var showEmptySections: Bool = false
    @AppStorage("ShowArchived") private var showArchived: Bool = false
    @AppStorage("ShowTrashed") private var showTrashed: Bool = false
    
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Toggle("Show Empty Sections", isOn: $showEmptySections)
                .keyboardShortcut("e", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Show Chats") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showArchived = false
                    showTrashed = false
                }
            }
            .keyboardShortcut("1", modifiers: [.command])
            
            Button("Show Archive") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showArchived = true
                    showTrashed = false
                }
            }
            .keyboardShortcut("2", modifiers: [.command])
            
            Button("Show Trash") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showArchived = false
                    showTrashed = true
                }
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
                    WebSearchConfigurationItem.self
                ]
            }
        }
    }
    
    /// Shared SwiftData container for managing persistent data
    /// Handles dialogs, projects, templates, and bookmarks
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            APIConfigurationItem.self,
            ModelItem.self,
            ConversationOptions.self,
            ConversationItem.self,            
            ProjectItem.self,
            BookmarkItem.self,
            PromptTemplate.self,
            VoiceConfigurationItem.self,
            WebSearchConfigurationItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, migrationPlan: ProjectMigrationPlan.self, configurations: modelConfiguration)
        } catch {
            vxAtelierPro.log.error("Failed to create ModelContainer: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // Create the QueryManager for centralized data access
    private let queryManager: QueryManager
    
    // Read the stored appearance preference
    @AppStorage("appearanceStyle") private var appearanceStyle: AppearanceStyle = .system
    private var effectiveColorScheme: ColorScheme? {
        switch appearanceStyle {
        case .system:
            return nil // Follow system, do not override
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    @State private var isDialogShown: Bool = false
    @State private var isLogHistoryShown: Bool = false
    @State private var logHistoryFilters: Set<LoggingService.LogType> = []
    
    init() {
        vxAtelierPro.log.debug("Initializing vxAtelierPro")

        vxAtelierPro.log.debug("Initializing Query Manager")
        self.queryManager = QueryManager(modelContext: sharedModelContainer.mainContext)
        vxAtelierPro.log.debug("Query Manager initialized")

        vxAtelierPro.log.debug("Initializing AIServiceManager")
        _ = AIServiceManager.shared
        vxAtelierPro.log.debug("AIServiceManager initialized")
        
        vxAtelierPro.log.debug("Registering Tools")
        registerDefaultTools()
        vxAtelierPro.log.debug("Tools registered")
        
        #if os(macOS)
        if UserDefaults.standard.bool(forKey: "MakeKeyAndOrderFront") {
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
        let registry = AIToolRegistry.shared
        let context = sharedModelContainer.mainContext
        
        // Dialog Tools
        registry.registerTool(ListDialogsTool(modelContext: context))
        registry.registerTool(RenameDialogTool(modelContext: context))
        registry.registerTool(FindDialogTool(modelContext: context))
        registry.registerTool(CurrentDialogTool())
        
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
            ContentView()
                .preferredColorScheme(effectiveColorScheme)
                .environment(\.showLogHistory) {
                    isLogHistoryShown = true
                }
                .sheet(isPresented: $isLogHistoryShown) {
                    LogHistorySheet(
                        filters: $logHistoryFilters
                    )
                }
        }        
        .modelContainer(sharedModelContainer)
        .environment(queryManager)
        .environment(TTSQueue(modelContext: sharedModelContainer.mainContext))
        .commands {
            AppCommands()
        }
                
#if os(macOS)
        // Settings scene keeps the user-selected appearance override
        Settings {
            ApplicationSettingsView()
                .preferredColorScheme(effectiveColorScheme)
                .environment(queryManager)
                .environment(\.modelContext, sharedModelContainer.mainContext)
        }
        
        MenuBarExtra("vxAtelier Pro", systemImage: "message.circle") {
            MenuBarContent()
        }
#endif
    }
}

// MARK: - Environment Keys
private struct ShowLogHistoryKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var showLogHistory: () -> Void {
        get { self[ShowLogHistoryKey.self] }
        set { self[ShowLogHistoryKey.self] = newValue }
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

/// Application delegate for macOS-specific behaviors
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        vxAtelierPro.log.debug("Application did finish launching")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let shouldTerminate = UserDefaults.standard.bool(forKey: "shouldTerminateAfterLastWindowClosed")
        vxAtelierPro.log.debug("Checking if should terminate after last window closed: \(shouldTerminate)")
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
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
}
