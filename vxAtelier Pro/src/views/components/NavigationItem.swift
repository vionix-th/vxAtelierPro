import SwiftData
import SwiftUI

struct NavigationItem: View {
    @Binding var title: String
    var subtitle: String
    let onDelete: () -> Void
    let onRename: (String) -> Void
    var onRestore: (() -> Void)?
    var onPermanentDelete: (() -> Void)?
    var onArchive: (() -> Void)?
    var imageName: String = ""
    var onProjectAssign: ((ProjectItem?) -> Void)?
    var onExport: (() -> Void)?
    var conversation: ConversationItem? = nil
    var project: ProjectItem? = nil

    @Environment(QueryManager.self) private var queryManager

    @State private var isHoveringItem: Bool = false
    @State private var isEditing: Bool = false
    @FocusState private var isEditingFocus: Bool

    @AppStorage("showConversationLastMessageLabel") private var showConversationLastMessageLabel: Bool = true
    @AppStorage("showConversationCreatedLabel") private var showConversationCreatedLabel: Bool = true

    @ViewBuilder
    private var navigationItemContextMenu: some View {
        Group {
            // Status-dependent actions
            if let onRestore = onRestore {
                Button {
                    onRestore()
                } label: {
                    MenuItemStyle.label("Restore", systemImage: "arrow.uturn.left")
                }
                .help("Restore this item")
            }

            // Rename action (only for active or archived items, not for trashed)
            if onPermanentDelete == nil {
                Button {
                    isEditing = true
                    isEditingFocus = true
                } label: {
                    MenuItemStyle.label("Rename", systemImage: "pencil")
                }
                .help("Rename this item")
            }

            // Only show project assignment for non-trashed items
            if let onProjectAssign = onProjectAssign, onPermanentDelete == nil {
                // Project assignment submenu
                Menu {
                    Button {
                        onProjectAssign(nil)
                    } label: {
                        MenuItemStyle.label(
                            "Remove from Project", systemImage: "folder.badge.minus")
                    }
                    .help("Remove from current project")

                    if !queryManager.activeProjects.isEmpty {
                        Divider()
                        ForEach(queryManager.activeProjects) { project in
                            Button {
                                onProjectAssign(project)
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
                    onExport()
                } label: {
                    MenuItemStyle.label("Export as JSON", systemImage: "arrow.up.doc")
                }
                .help("Export this item to JSON")
            }

            // Delete actions
            Divider()

            if let onArchive = onArchive {
                Button {
                    onArchive()
                } label: {
                    MenuItemStyle.label("Move to Archive", systemImage: "archivebox")
                }
                .help("Move this item to archive")
            }

            if let onPermanentDelete = onPermanentDelete {
                Button(role: .destructive) {
                    onPermanentDelete()
                } label: {
                    MenuItemStyle.label("Delete Permanently", systemImage: "trash.fill")
                }
                .help("Permanently delete this item")
            } else {
                Button(role: .destructive) {
                    onDelete()
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
                    TextField("Enter title", text: $title)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingFocus)
                        .onSubmit {
                            isEditing = false
                            onRename(title)
                        }
                        #if os(macOS)
                            .onExitCommand {
                                isEditing = false
                                onRename(title)
                            }
                        #endif
                } else {
                    Text(title)
                        .font(.headline)
                }
                if let conversation = conversation {
                    let sortedTurns = conversation.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
                    if showConversationLastMessageLabel {
                        if sortedTurns.isEmpty {
                            Text("no messages")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            let lastTurn = sortedTurns.last!
                            let lastTimestamp: Date =
                                lastTurn.events.last?.message.timestamp ?? lastTurn.userMessage.timestamp
                            Text(lastTimestamp.formatted(.dateTime.year().month().day().hour().minute()))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    if showConversationCreatedLabel {
                        Text(conversation.timestamp.formatted(.dateTime.year().month().day().hour().minute()))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let project = project {
                    if showConversationLastMessageLabel {
                        if let lastMsg = ProjectSorter.lastTurnTimestamp(for: project) {
                            Text(lastMsg.formatted(.dateTime.year().month().day().hour().minute()))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("no messages")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    if showConversationCreatedLabel {
                        Text(project.timestamp.formatted(.dateTime.year().month().day().hour().minute()))
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
                    && UserDefaults.standard.bool(forKey: "showRowToolButtons")
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
}
