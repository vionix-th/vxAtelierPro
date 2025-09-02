import SwiftUI

public enum SidebarSortType: String, CaseIterable, Identifiable {
    case conversationDate
    case lastMessageDate
    case alphabetically
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .conversationDate: return "By Conversation Date"
        case .lastMessageDate: return "By Last Message Date"
        case .alphabetically: return "Alphabetically"
        }
    }
    public var systemImage: String {
        switch self {
        case .conversationDate: return "calendar"
        case .lastMessageDate: return "bubble.left.and.bubble.right"
        case .alphabetically: return "textformat.abc"
        }
    }
}

public struct SidebarSortButton: View {
    @Binding public var sortDescending: Bool
    @Binding public var sortTypeRaw: String
    public let allowedTypes: [SidebarSortType]
    public init(sortDescending: Binding<Bool>, sortTypeRaw: Binding<String>, allowedTypes: [SidebarSortType]) {
        self._sortDescending = sortDescending
        self._sortTypeRaw = sortTypeRaw
        self.allowedTypes = allowedTypes
    }
    public var sortType: SidebarSortType { SidebarSortType(rawValue: sortTypeRaw) ?? allowedTypes.first! }
    public var body: some View {
        #if os(iOS)
        Menu {
            Button(action: { sortDescending.toggle() }) {
                Label(sortDescending ? "Descending" : "Ascending", systemImage: sortDescending ? "arrow.down" : "arrow.up")
            }
            Divider()
            Picker("Sort Type", selection: $sortTypeRaw) {
                ForEach(allowedTypes) { type in
                    Label(type.label, systemImage: type.systemImage)
                        .tag(type.rawValue)
                }
            }
        } label: {
            Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
        }
        .buttonStyle(.borderless)
        .help({
            let typeLabel = sortType.label
            let order = sortDescending ? "Descending" : "Ascending"
            return "Sort: \(typeLabel), \(order)"
        }())
        #else
        Button {
            sortDescending.toggle()
        } label: {
            Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
        }
        .buttonStyle(.borderless)
        .help({
            let typeLabel = sortType.label
            let order = sortDescending ? "Descending" : "Ascending"
            return "Sort: \(typeLabel), \(order)"
        }())
        .contextMenu {
            Button(action: { sortDescending.toggle() }) {
                Label(sortDescending ? "Descending" : "Ascending", systemImage: sortDescending ? "arrow.down" : "arrow.up")
            }
            Divider()
            ForEach(allowedTypes) { type in
                Button(action: { sortTypeRaw = type.rawValue }) {
                    Label(type.label, systemImage: type.systemImage)
                    if sortType == type {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        #endif
    }
} 