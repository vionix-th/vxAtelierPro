import SwiftUI

#if os(macOS)
/// Native macOS Settings scene root.
struct MacOSApplicationSettingsSceneView: View {
    @AppStorage(AppSettings.Keys.selectedMacSettingsSection) private var selectedSectionRaw =
        AppDefaults.selectedMacSettingsSection
    @AppStorage(AppSettings.Keys.selectedSettingsDestination) private var selectedDestinationRaw =
        AppDefaults.selectedSettingsDestination

    private var selectedSection: Binding<MacOSSettingsSection> {
        Binding(
            get: { MacOSSettingsSection(rawValue: selectedSectionRaw) ?? .general },
            set: { selectedSectionRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedSection) {
            ForEach(MacOSSettingsSection.allCases) { section in
                MacOSSettingsSectionView(
                    section: section,
                    selectedDestinationRaw: $selectedDestinationRaw
                )
                .tabItem {
                    Label(section.title, systemImage: section.systemImage)
                }
                .tag(section)
            }
        }
        // this seem obserdly large: .scenePadding()
        .frame(minWidth: 720, minHeight: 520)
        .environment(\.settingsPresentationStyle, .macSettingsScene)
        .onAppear {
            ensureSelectedDestination(in: selectedSection.wrappedValue)
        }
        .onChange(of: selectedSectionRaw) { _, rawValue in
            ensureSelectedDestination(in: MacOSSettingsSection(rawValue: rawValue) ?? .general)
        }
        .onChange(of: selectedDestinationRaw) { _, rawValue in
            let destination = SettingsDestination(rawValue: rawValue)
            selectedSectionRaw = MacOSSettingsSection.section(containing: destination).rawValue
        }
    }

    private func ensureSelectedDestination(in section: MacOSSettingsSection) {
        let destination = SettingsDestination(rawValue: selectedDestinationRaw)
        guard let destination, section.destinations.contains(destination) else {
            selectedDestinationRaw = section.destinations.first?.rawValue ?? SettingsDestination.general.rawValue
            return
        }
    }
}

/// One macOS Settings section with its destination picker and content.
private struct MacOSSettingsSectionView: View {
    let section: MacOSSettingsSection
    @Binding var selectedDestinationRaw: String

    private var selectedDestination: SettingsDestination {
        let destination = SettingsDestination(rawValue: selectedDestinationRaw)
        if let destination, section.destinations.contains(destination) {
            return destination
        }
        return section.destinations.first ?? .general
    }

    private var destinationBinding: Binding<String> {
        Binding(
            get: { selectedDestination.rawValue },
            set: { selectedDestinationRaw = $0 }
        )
    }

    var body: some View {
        VStack(spacing: AppDefaults.paddingLarge) {
            if section.destinations.count > 1 {
                let picker = Picker(section.title, selection: destinationBinding) {
                    ForEach(section.destinations) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination.rawValue)
                    }
                }
                if section.destinations.count <= 4 {
                    picker
                        .pickerStyle(.segmented)
                        .labelsHidden()
                } else {
                    picker
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsDestinationView(destination: selectedDestination)
        }
    }
}
#endif
