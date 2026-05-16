import SwiftData
import SwiftUI

struct ContentSidebarActions {
    let deleteProject: (PersistentIdentifier) -> Void
    let restoreProject: (PersistentIdentifier) -> Void
    let archiveProject: (PersistentIdentifier) -> Void
    let renameProject: (PersistentIdentifier, String) -> Void
    let requestExportProject: (PersistentIdentifier) -> Void
    let deleteConversation: (PersistentIdentifier) -> Void
    let restoreConversation: (PersistentIdentifier) -> Void
    let archiveConversation: (PersistentIdentifier) -> Void
    let renameConversation: (PersistentIdentifier, String) -> Void
    let assignConversationToProject: (PersistentIdentifier, PersistentIdentifier?) -> Void
    let requestExportConversation: (PersistentIdentifier) -> Void
    let deleteBookmarkFromContext: (PersistentIdentifier) -> Void
    let deleteBookmarkFromSwipe: (PersistentIdentifier) -> Void
    let renameBookmark: (PersistentIdentifier, String) -> Void
    let selectBookmark: (PersistentIdentifier) -> Void
}

struct ContentSidebarView: View {
    let contentFilter: ContentFilter
    let projects: [ProjectItem]
    let conversations: [ConversationItem]
    let bookmarks: [BookmarkItem]
    @Binding var selection: SidebarSelection?
    @Binding var sidebarProjectsSortDescending: Bool
    @Binding var sidebarProjectsSortTypeRaw: String
    @Binding var sidebarConversationsSortDescending: Bool
    @Binding var sidebarConversationsSortTypeRaw: String
    let showEmptySections: Bool
    let actions: ContentSidebarActions
    let availableProjects: [ProjectItem]

    private var titleForProjects: String {
        switch contentFilter {
        case .active: return "Projects"
        case .archived: return "Archived Projects"
        case .trashed: return "Trashed Projects"
        }
    }

    private var titleForConversations: String {
        switch contentFilter {
        case .active: return "Standalone Conversations"
        case .archived: return "Archived Conversations"
        case .trashed: return "Trashed Conversations"
        }
    }

    var body: some View {
        List(selection: $selection) {
            projectSection(title: titleForProjects, projects: projects)
            conversationSection(title: titleForConversations, conversations: conversations)

            if contentFilter == .active {
                bookmarkSection(title: "Bookmarks", bookmarks: bookmarks)
            }
        }
    }

    func projectNavigationLink(for project: ProjectItem) -> some View {
        NavigationLink(value: SidebarSelection.project(project.id)) {
            NavigationItem(
                itemID: project.id,
                title: project.name,
                subtitle: project.timestamp.formatted(.dateTime.year().month().day().hour().minute()),
                onDelete: actions.deleteProject,
                onRename: actions.renameProject,
                onRestore: project.status != .active ? actions.restoreProject : nil,
                onPermanentDelete: project.status == .trashed ? actions.deleteProject : nil,
                onArchive: project.status == .active ? actions.archiveProject : nil,
                imageName: "folder",
                onProjectAssign: nil,
                onExport: actions.requestExportProject,
                details: NavigationItemDetails(
                    lastMessageTimestamp: lastMessageTimestamp(for: project),
                    createdTimestamp: project.timestamp,
                    isUtilityConversation: false
                )
            )
        }
    }

    func conversationNavigationLink(for conversation: ConversationItem) -> some View {
        NavigationLink(value: SidebarSelection.conversation(conversation.id)) {
            NavigationItem(
                itemID: conversation.id,
                title: conversation.title,
                subtitle: conversation.timestamp.formatted(.dateTime.year().month().day().hour().minute()),
                onDelete: actions.deleteConversation,
                onRename: actions.renameConversation,
                onRestore: conversation.status != .active ? actions.restoreConversation : nil,
                onPermanentDelete: conversation.status == .trashed ? actions.deleteConversation : nil,
                onArchive: conversation.status == .active ? actions.archiveConversation : nil,
                imageName: AppDefaults.conversationImageSystemName,
                onProjectAssign: conversation.status == .active ? actions.assignConversationToProject : nil,
                onExport: actions.requestExportConversation,
                details: NavigationItemDetails(
                    lastMessageTimestamp: lastMessageTimestamp(for: conversation),
                    createdTimestamp: conversation.timestamp,
                    isUtilityConversation: conversation.isUtilityConversation
                ),
                availableProjects: availableProjects.map {
                    NavigationProjectOption(id: $0.id, name: $0.name)
                }
            )
        }
    }

    func bookmarkRow(for bookmark: BookmarkItem) -> some View {
        NavigationItem(
            itemID: bookmark.id,
            title: bookmark.label,
            subtitle: bookmark.turn?.conversation?.title ?? "(missing)",
            onDelete: actions.deleteBookmarkFromContext,
            onRename: actions.renameBookmark,
            imageName: "bookmark"
        )
        .contentShape(Rectangle())
        .onTapGesture {
            actions.selectBookmark(bookmark.id)
        }
    }

    @ViewBuilder
    private func projectSection(title: String, projects: [ProjectItem]) -> some View {
        if !projects.isEmpty || showEmptySections {
            let sorted = ProjectSorter.sort(
                projects,
                descending: sidebarProjectsSortDescending,
                sortType: SidebarSortType(rawValue: sidebarProjectsSortTypeRaw) ?? .alphabetically,
                contentFilter: contentFilter
            )
            Section {
                ForEach(sorted) { project in
                    projectNavigationLink(for: project)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        if index < sorted.count {
                            actions.deleteProject(sorted[index].id)
                        } else {
                            vxAtelierPro.log.warning(
                                "ContentSidebarView: Invalid index \(index) encountered in projectSection.onDelete for projects array count \(projects.count)."
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    SidebarSortButton(
                        sortDescending: $sidebarProjectsSortDescending,
                        sortTypeRaw: $sidebarProjectsSortTypeRaw,
                        allowedTypes: [.alphabetically]
                    )
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private func conversationSection(title: String, conversations: [ConversationItem]) -> some View {
        if !conversations.isEmpty || showEmptySections {
            let sorted = ConversationSorter.sort(
                conversations,
                descending: sidebarConversationsSortDescending,
                sortType: SidebarSortType(rawValue: sidebarConversationsSortTypeRaw) ?? .conversationDate
            )
            Section {
                ForEach(sorted) { conversation in
                    conversationNavigationLink(for: conversation)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        if index < sorted.count {
                            actions.deleteConversation(sorted[index].id)
                        } else {
                            vxAtelierPro.log.warning(
                                "ContentSidebarView: Invalid index \(index) encountered in conversationSection.onDelete for conversations array count \(conversations.count)."
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    SidebarSortButton(
                        sortDescending: $sidebarConversationsSortDescending,
                        sortTypeRaw: $sidebarConversationsSortTypeRaw,
                        allowedTypes: SidebarSortType.allCases
                    )
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private func bookmarkSection(title: String, bookmarks: [BookmarkItem]) -> some View {
        if !bookmarks.isEmpty || showEmptySections {
            Section(title) {
                ForEach(bookmarks) { bookmark in
                    bookmarkRow(for: bookmark)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        if index < bookmarks.count {
                            actions.deleteBookmarkFromSwipe(bookmarks[index].id)
                        } else {
                            vxAtelierPro.log.warning(
                                "ContentSidebarView: Invalid index \(index) encountered in bookmarkSection.onDelete for bookmarks array count \(bookmarks.count)."
                            )
                        }
                    }
                }
            }
        }
    }

    private func lastMessageTimestamp(for conversation: ConversationItem) -> Date? {
        let sortedTurns = conversation.turns.sorted { $0.sequenceNumber < $1.sequenceNumber }
        guard let lastTurn = sortedTurns.last else { return nil }
        return lastTurn.events.last?.message.timestamp ?? lastTurn.userMessage.timestamp
    }

    private func lastMessageTimestamp(for project: ProjectItem) -> Date? {
        ProjectSorter.lastTurnTimestamp(for: project)
    }
}
