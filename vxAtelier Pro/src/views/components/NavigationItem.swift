import Foundation
import SwiftData
import SwiftUI

struct NavigationProjectOption: Identifiable {
    let id: PersistentIdentifier
    let name: String
}

struct NavigationItemDetails {
    let lastMessageTimestamp: Date?
    let createdTimestamp: Date
    let isUtilityConversation: Bool
}

struct NavigationItem: View {
    let itemID: PersistentIdentifier
    let title: String
    let subtitle: String
    let onDelete: (PersistentIdentifier) -> Void
    let onRename: (PersistentIdentifier, String) -> Void
    var onRestore: ((PersistentIdentifier) -> Void)?
    var onPermanentDelete: ((PersistentIdentifier) -> Void)?
    var onArchive: ((PersistentIdentifier) -> Void)?
    var imageName: String = ""
    var onProjectAssign: ((PersistentIdentifier, PersistentIdentifier?) -> Void)?
    var onExport: ((PersistentIdentifier) -> Void)?
    var details: NavigationItemDetails?
    var availableProjects: [NavigationProjectOption] = []

    @State private var isHoveringItem: Bool = false
    @State private var isEditing: Bool = false
    @State private var draftTitle: String = ""
    @FocusState private var isEditingFocus: Bool

    @AppStorage(AppSettings.Keys.showConversationLastMessageLabel) private var showConversationLastMessageLabel: Bool = true
    @AppStorage(AppSettings.Keys.showConversationCreatedLabel) private var showConversationCreatedLabel: Bool = true

    @ViewBuilder
    private var navigationItemContextMenu: some View {
        Group {
            if let onRestore = onRestore {
                Button {
                    onRestore(itemID)
                } label: {
                    MenuItemStyle.label("Restore", systemImage: "arrow.uturn.left")
                }
                .help("Restore this item")
            }

            if onPermanentDelete == nil {
                Button {
                    isEditing = true
                    draftTitle = title
                    isEditingFocus = true
                } label: {
                    MenuItemStyle.label("Rename", systemImage: "pencil")
                }
                .help("Rename this item")
            }

            if let onProjectAssign = onProjectAssign, onPermanentDelete == nil {
                Menu {
                    Button {
                        onProjectAssign(itemID, nil)
                    } label: {
                        MenuItemStyle.label("Remove from Project", systemImage: "folder.badge.minus")
                    }
                    .help("Remove from current project")

                    if !availableProjects.isEmpty {
                        Divider()
                        ForEach(availableProjects) { project in
                            Button {
                                onProjectAssign(itemID, project.id)
                            } label: {
                                MenuItemStyle.label(project.name, systemImage: "folder")
                            }
                            .help("Move to project \(project.name)")
                        }
                    }
                } label: {
                    MenuItemStyle.label("Move to Project", systemImage: "folder.badge.plus")
                }
            }

            if let onExport = onExport {
                Divider()

                Button {
                    onExport(itemID)
                } label: {
                    MenuItemStyle.label("Export as JSON", systemImage: "arrow.up.doc")
                }
                .help("Export this item to JSON")
            }

            Divider()

            if let onArchive = onArchive {
                Button {
                    onArchive(itemID)
                } label: {
                    MenuItemStyle.label("Move to Archive", systemImage: "archivebox")
                }
                .help("Move this item to archive")
            }

            if let onPermanentDelete = onPermanentDelete {
                Button(role: .destructive) {
                    onPermanentDelete(itemID)
                } label: {
                    MenuItemStyle.label("Delete Permanently", systemImage: "trash.fill")
                }
                .help("Permanently delete this item")
            } else {
                Button(role: .destructive) {
                    onDelete(itemID)
                } label: {
                    MenuItemStyle.label("Move to Trash", systemImage: "trash")
                }
                .help("Move this item to trash")
            }
        }
    }

    var body: some View {
        HStack {
            Image(systemName: imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading) {
                if isEditing {
                    TextField("Enter title", text: $draftTitle)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingFocus)
                        .onSubmit {
                            commitRename()
                        }
                        #if os(macOS)
                            .onExitCommand {
                                commitRename()
                            }
                        #endif
                } else {
                    HStack(spacing: 6) {
                        if details?.isUtilityConversation == true {
                            Image(systemName: "menubar.dock.rectangle")
                                .foregroundColor(.green)
                                .font(.caption)
                                .help("Linked to utility panel")
                        }

                        Text(title)
                            .font(.headline)
                    }
                }

                if let details {
                    if showConversationLastMessageLabel {
                        if let lastTimestamp = details.lastMessageTimestamp {
                            Text(lastTimestamp.formatted(.dateTime.year().month().day().hour().minute()))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("no messages")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if showConversationCreatedLabel {
                        Text(details.createdTimestamp.formatted(.dateTime.year().month().day().hour().minute()))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(subtitle)
                        .font(.subheadline)
                }
            }

            Spacer()

            Menu {
                navigationItemContextMenu
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.gray)
                    .font(.title2)
            }
            .frame(width: 40, height: 40, alignment: .center)
            .menuStyle(.borderlessButton)
            .opacity(
                isHoveringItem
                    && UserDefaults.standard.bool(forKey: AppSettings.Keys.showRowToolButtons)
                    ? 1 : 0)
        }
        .padding(AppDefaults.paddingMedium)
        .onHover { hovering in
            isHoveringItem = hovering
        }
        .contextMenu {
            navigationItemContextMenu
        }
        .frame(minHeight: 60)
    }

    private func commitRename() {
        isEditing = false
        onRename(itemID, draftTitle)
    }
}
