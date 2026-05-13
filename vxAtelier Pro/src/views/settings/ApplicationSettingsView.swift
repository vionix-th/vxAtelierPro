import SwiftUI

struct ApplicationSettingsView: View {
    typealias SettingsTab = SettingsDestination

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: SettingsTab?
    @State private var compactPath: [SettingsTab]
    private let initialTab: SettingsTab?

    init(initialTab: SettingsTab? = nil) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab ?? .general)
        _compactPath = State(initialValue: initialTab.map { [$0] } ?? [])
    }

    var body: some View {
        settingsContainer
        .onAppear {
            vxAtelierPro.log.debug("ApplicationSettingsView appeared")
            if let initialTab = initialTab {
                selectedTab = initialTab
                if compactPath.isEmpty {
                    compactPath = [initialTab]
                }
            }
        }
    }

    @ViewBuilder
    private var settingsContainer: some View {
        #if os(macOS)
        splitSettingsView
        #else
        if horizontalSizeClass == .compact {
            compactSettingsView
        } else {
            splitSettingsView
        }
        #endif
    }

    private var splitSettingsView: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Settings")
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(190)
        } detail: {
            SettingsDestinationView(destination: selectedTab ?? .general)
        }
    }

    private var compactSettingsView: some View {
        NavigationStack(path: $compactPath) {
            List(SettingsDestination.allCases) { destination in
                NavigationLink(value: destination) {
                    Label(destination.title, systemImage: destination.systemImage)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                SettingsDestinationView(destination: destination)
            }
        }
    }

    private var sidebar: some View {
        List(SettingsDestination.allCases, id: \.self, selection: $selectedTab) { destination in
            NavigationLink(value: destination) {
                Label(destination.title, systemImage: destination.systemImage)
            }
        }
    }
}

struct SettingsDestinationView: View {
    let destination: SettingsDestination

    var body: some View {
        destination.content
    }
}
