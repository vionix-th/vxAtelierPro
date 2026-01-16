import Foundation

@MainActor
struct ContentSidebarDataSource {
    let navigationMode: NavigationMode
    let projects: [ProjectItem]
    let dialogs: [ConversationItem]
    let bookmarks: [BookmarkItem]
    let projectTitle: String
    let dialogTitle: String

    init(
        queryManager: QueryManager,
        navigationMode: NavigationMode,
        showSystemDialogs: Bool
    ) {
        self.navigationMode = navigationMode

        switch navigationMode {
        case .chats:
            projects = queryManager.activeProjects
            projectTitle = "Projects"
            dialogTitle = "Standalone Dialogs"
        case .archive:
            projects = queryManager.archivedProjects
            projectTitle = "Archived Projects"
            dialogTitle = "Archived Dialogs"
        case .trash:
            projects = queryManager.trashedProjects
            projectTitle = "Trashed Projects"
            dialogTitle = "Trashed Items"
        }

        dialogs = queryManager.standaloneConversations(
            showSystemDialogs: showSystemDialogs,
            navigationMode: navigationMode
        )

        if navigationMode == .chats {
            bookmarks = queryManager.bookmarks.sorted {
                let comparison = $0.label.localizedCaseInsensitiveCompare($1.label)
                if comparison == .orderedSame { return false }
                return comparison == .orderedAscending
            }
        } else {
            bookmarks = []
        }
    }

    var hasVisibleItems: Bool {
        !projects.isEmpty || !dialogs.isEmpty || !bookmarks.isEmpty
    }

    var visibleSelections: [SidebarSelection] {
        projects.map { .project($0.id) }
            + dialogs.map { .conversation($0.id) }
    }
}
