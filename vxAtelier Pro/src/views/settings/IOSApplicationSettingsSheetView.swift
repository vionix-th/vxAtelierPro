import SwiftUI

#if os(iOS)
/// iOS Settings sheet root with compact and regular width layouts.
struct IOSApplicationSettingsSheetView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDestination: SettingsDestination?
    @State private var compactPath: [SettingsDestination]
    private let initialDestination: SettingsDestination?

    init(initialDestination: SettingsDestination? = nil) {
        self.initialDestination = initialDestination
        _selectedDestination = State(initialValue: initialDestination ?? .general)
        _compactPath = State(initialValue: initialDestination.map { [$0] } ?? [])
    }

    var body: some View {
        settingsContainer
            .onAppear {
                vxAtelierPro.log.debug("IOSApplicationSettingsSheetView appeared")
                if let initialDestination {
                    selectedDestination = initialDestination
                    if compactPath.isEmpty {
                        compactPath = [initialDestination]
                    }
                }
            }
    }

    @ViewBuilder
    private var settingsContainer: some View {
        if horizontalSizeClass == .compact {
            compactSettingsView
        } else {
            splitSettingsView
        }
    }

    private var splitSettingsView: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Settings")
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(190)
        } detail: {
            SettingsDestinationView(destination: selectedDestination ?? .general)
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
        List(SettingsDestination.allCases, id: \.self, selection: $selectedDestination) { destination in
            NavigationLink(value: destination) {
                Label(destination.title, systemImage: destination.systemImage)
            }
        }
    }
}
#endif
