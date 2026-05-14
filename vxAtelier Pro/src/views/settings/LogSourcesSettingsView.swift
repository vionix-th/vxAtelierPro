import Foundation
import SwiftUI

private let logSourcesKey = "LoggingService.sources"

struct LogSourcesSettingsView: View {
    @State private var sources: [LogSource: Bool] = [:]
    @State private var searchText = ""

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredSources: [LogSource] {
        sources.keys.filter { source in
            searchText.isEmpty ||
            source.file.localizedCaseInsensitiveContains(searchText) ||
            source.function.localizedCaseInsensitiveContains(searchText)
        }
            .sorted(by: logSourceSort)
    }

    var body: some View {
        SettingsSearchListPage(
            title: "Log Sources",
            searchContent: {
                VStack(spacing: AppDefaults.paddingMedium) {
                    SettingsPageActionRegion(padded: false) {
                        sourceActionsMenu
                    }
                    SettingsSearchField(prompt: "Filter log sources", text: $searchText)
                }
            },
            content: {
                content
            }
        )
        .settingsNavigationActions {
            sourceActionsMenu
        }
        .onAppear(perform: loadSources)
    }

    private var sourceActionsMenu: some View {
        Menu {
            Button {
                setFilteredSources(enabled: true)
            } label: {
                Label(isFiltering ? "Enable Matching Sources" : "Enable All Sources", systemImage: "checkmark.circle")
            }
            .disabled(filteredSources.isEmpty)

            Button {
                setFilteredSources(enabled: false)
            } label: {
                Label(isFiltering ? "Disable Matching Sources" : "Disable All Sources", systemImage: "xmark.circle")
            }
            .disabled(filteredSources.isEmpty)
        } label: {
            Label("Source Actions", systemImage: "ellipsis.circle")
        }
        .disabled(sources.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty {
            SettingsEmptyState(
                title: "No Log Sources",
                systemImage: "list.bullet.rectangle",
                description: "No log sources are registered yet."
            )
        } else if filteredSources.isEmpty {
            SettingsEmptyState(
                title: "No Matching Sources",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "No log sources match \"\(searchText)\"."
            )
        } else {
            SettingsEntityList(
                items: filteredSources,
                emptyTitle: "No Log Sources",
                emptySystemImage: "list.bullet.rectangle",
                emptyDescription: "No log sources are registered yet."
            ) { source in
                SettingsToggleRow(
                    source.file,
                    subtitle: source.function,
                    isOn: sourceBinding(for: source)
                )
            }
        }
    }

    private func loadSources() {
        guard let data = UserDefaults.standard.data(forKey: logSourcesKey) else {
            sources = [:]
            return
        }
        do {
            sources = try JSONDecoder().decode([LogSource: Bool].self, from: data)
        } catch {
            sources = [:]
            vxAtelierPro.log.error("Failed to decode log sources: \(error.localizedDescription)")
        }
    }

    private func sourceBinding(for source: LogSource) -> Binding<Bool> {
        Binding(
            get: { sources[source, default: true] },
            set: { newValue in
                sources[source] = newValue
                saveSources()
            }
        )
    }

    private func saveSources() {
        do {
            let data = try JSONEncoder().encode(sources)
            UserDefaults.standard.set(data, forKey: logSourcesKey)
        } catch {
            vxAtelierPro.log.error("Failed to save log sources: \(error.localizedDescription)")
        }
    }

    private func setFilteredSources(enabled: Bool) {
        for source in filteredSources {
            sources[source] = enabled
        }
        saveSources()
    }

    private func logSourceSort(lhs: LogSource, rhs: LogSource) -> Bool {
        if lhs.file == rhs.file {
            return lhs.function < rhs.function
        }
        return lhs.file < rhs.file
    }
}
