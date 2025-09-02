import SwiftUI
import SwiftData

struct AppearanceWrapperView: View {
    @AppStorage("appearanceStyle") private var appearanceStyle: AppearanceStyle = .system
    @Environment(\.colorScheme) private var systemColorScheme

    var effectiveColorScheme: ColorScheme? {
        switch appearanceStyle {
        case .system:
            return nil // Follow system, do not override
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var body: some View {
        ContentView()
            .preferredColorScheme(effectiveColorScheme)
    }
}

struct AppearanceWrapperForSettingsView: View {
    let queryManager: QueryManager
    let modelContext: ModelContext
    @AppStorage("appearanceStyle") private var appearanceStyle: AppearanceStyle = .system
    @Environment(\.colorScheme) private var systemColorScheme

    var effectiveColorScheme: ColorScheme? {
        switch appearanceStyle {
        case .system:
            return nil // Follow system, do not override
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var body: some View {
        ApplicationSettingsView()
            .preferredColorScheme(effectiveColorScheme)
            .environment(queryManager)
            .environment(\EnvironmentValues.modelContext, modelContext)
        #if os(macOS)
            .frame(idealWidth: 900, idealHeight: 640)
        #else
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #endif            
    }    
} 