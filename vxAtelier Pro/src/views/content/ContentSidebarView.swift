import SwiftData
import SwiftUI

struct ContentSidebarActions {
    let deleteItem: (any PersistentModel) -> Void
    let restoreItem: (any PersistentModel) -> Void
    let archiveItem: (any PersistentModel) -> Void
    let assignConversationToProject: (ConversationItem, ProjectItem?) -> Void
    let requestExportProject: (ProjectItem) -> Void
    let requestExportConversation: (ConversationItem) -> Void
    let deleteBookmarkFromContext: (BookmarkItem) -> Void
    let deleteBookmarkFromSwipe: (BookmarkItem) -> Void
    let selectBookmark: (BookmarkItem) -> Void
}

struct ContentSidebarView: View {
    let dataSource: ContentSidebarDataSource
    @Binding var selection: SidebarSelection?
    @Binding var sidebarProjectsSortDescending: Bool
    @Binding var sidebarProjectsSortTypeRaw: String
    @Binding var sidebarDialogsSortDescending: Bool
    @Binding var sidebarDialogsSortTypeRaw: String
    let showEmptySections: Bool
    let actions: ContentSidebarActions

    var body: some View {
        List(selection: $selection) {
            projectSection(
                title: dataSource.projectTitle,
                projects: dataSource.projects
            )

            dialogSection(
                title: dataSource.dialogTitle,
                dialogs: dataSource.dialogs
            )

            if dataSource.navigationMode == .chats {
                bookmarkSection(title: "Bookmarks", bookmarks: dataSource.bookmarks)
            }
        }
    }

    // MARK: - Navigation Links
    func projectNavigationLink(for project: ProjectItem) -> some View {
        NavigationLink(value: SidebarSelection.project(project.id)) {
            NavigationItem(
                title: Binding(get: { project.name }, set: { project.name = $0 }),
                subtitle: project.timestamp.formatted(
                    .dateTime.year().month().day().hour().minute()),
                onDelete: {
                    actions.deleteItem(project)
                },
                onRename: { project.name = $0 },
                onRestore: project.status != .active
                    ? {
                        actions.restoreItem(project)
                    } : nil,
                onPermanentDelete: project.status == .trashed
                    ? {
                        actions.deleteItem(project)
                    } : nil,
                onArchive: project.status == .active
                    ? {
                        actions.archiveItem(project)
                    } : nil,
                imageName: "folder",
                onProjectAssign: { _ in },
                onExport: {
                    actions.requestExportProject(project)
                },
                project: project
            )
        }
    }

    func conversationNavigationLink(for conversation: ConversationItem) -> some View {
        NavigationLink(value: SidebarSelection.conversation(conversation.id)) {
            NavigationItem(
                title: Binding(get: { conversation.title }, set: { conversation.title = $0 }),
                subtitle: conversation.timestamp.formatted(
                    .dateTime.year().month().day().hour().minute()),
                onDelete: {
                    actions.deleteItem(conversation)
                },
                onRename: { conversation.title = $0 },
                onRestore: conversation.status != .active
                    ? {
                        actions.restoreItem(conversation)
                    } : nil,
                onPermanentDelete: conversation.status == .trashed
                    ? {
                        actions.deleteItem(conversation)
                    } : nil,
                onArchive: conversation.status == .active
                    ? {
                        actions.archiveItem(conversation)
                    } : nil,
                imageName: AppDefaults.dialogImageSystemName,
                onProjectAssign: conversation.status == .active
                    ? { project in
                        actions.assignConversationToProject(conversation, project)
                    } : nil,
                onExport: {
                    actions.requestExportConversation(conversation)
                },
                conversation: conversation
            )
        }
    }

    func bookmarkRow(for bookmark: BookmarkItem) -> some View {
        NavigationItem(
            title: Binding(get: { bookmark.label }, set: { bookmark.label = $0 }),
            subtitle: bookmark.turn?.conversation?.title ?? "(missing)",
            onDelete: {
                actions.deleteBookmarkFromContext(bookmark)
            },
            onRename: {
                bookmark.label = $0
            },
            imageName: "bookmark"
        )
        .contentShape(Rectangle())
        .onTapGesture {
            actions.selectBookmark(bookmark)
        }
    }

    @ViewBuilder
    private func projectSection(title: String, projects: [ProjectItem]) -> some View {
        if !projects.isEmpty || showEmptySections {
            let sorted = ProjectSorter.sort(
                projects,
                descending: sidebarProjectsSortDescending,
                sortType: SidebarSortType(rawValue: sidebarProjectsSortTypeRaw)
                    ?? .alphabetically,
                navigationMode: dataSource.navigationMode
            )
            Section {
                ForEach(
                    sorted
                ) { project in
                    projectNavigationLink(for: project)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        if index < sorted.count {
                            let project = sorted[index]
                            actions.deleteItem(project)
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
                        allowedTypes: [.alphabetically])
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private func dialogSection(title: String, dialogs: [ConversationItem]) -> some View {
        if !dialogs.isEmpty || showEmptySections {
            let sorted = ConversationSorter.sort(
                dialogs,
                descending: sidebarDialogsSortDescending,
                sortType: SidebarSortType(rawValue: sidebarDialogsSortTypeRaw)
                    ?? .conversationDate
            )
            Section {
                ForEach(
                    sorted
                ) { dialog in
                    conversationNavigationLink(for: dialog)
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        if index < sorted.count {
                            let dialog = sorted[index]
                            actions.deleteItem(dialog)
                        } else {
                            vxAtelierPro.log.warning(
                                "ContentSidebarView: Invalid index \(index) encountered in dialogSection.onDelete for dialogs array count \(dialogs.count)."
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    SidebarSortButton(
                        sortDescending: $sidebarDialogsSortDescending,
                        sortTypeRaw: $sidebarDialogsSortTypeRaw,
                        allowedTypes: SidebarSortType.allCases)
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
                            let bookmark = bookmarks[index]
                            actions.deleteBookmarkFromSwipe(bookmark)
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
}
