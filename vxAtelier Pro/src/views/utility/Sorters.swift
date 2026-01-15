import Foundation

struct ConversationSorter {
    static func lastTurnTimestamp(for conversation: ConversationItem) -> Date? {
        guard let lastTurn = conversation.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) else {
            return nil
        }
        return lastTurn.events.last?.message.timestamp ?? lastTurn.userMessage.timestamp
    }

    static func sort(
        _ conversations: [ConversationItem],
        descending: Bool,
        sortType: SidebarSortType
    ) -> [ConversationItem] {
        switch sortType {
        case .conversationDate:
            return conversations.sorted {
                descending ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp
            }
        case .lastMessageDate:
            return conversations.sorted {
                let lhsDate = lastTurnTimestamp(for: $0) ?? $0.timestamp
                let rhsDate = lastTurnTimestamp(for: $1) ?? $1.timestamp
                return descending ? lhsDate > rhsDate : lhsDate < rhsDate
            }
        case .alphabetically:
            return conversations.sorted {
                descending
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending
                    : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}

struct ProjectSorter {
    static func lastTurnTimestamp(for project: ProjectItem) -> Date? {
        project.conversations.compactMap { ConversationSorter.lastTurnTimestamp(for: $0) }.max()
    }

    static func sort(
        _ projects: [ProjectItem],
        descending: Bool,
        sortType: SidebarSortType
    ) -> [ProjectItem] {
        switch sortType {
        case .alphabetically:
            return projects.sorted {
                descending
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .conversationDate:
            return projects.sorted {
                descending ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp
            }
        case .lastMessageDate:
            return projects.sorted {
                let lhsDate = lastTurnTimestamp(for: $0) ?? $0.timestamp
                let rhsDate = lastTurnTimestamp(for: $1) ?? $1.timestamp
                return descending ? lhsDate > rhsDate : lhsDate < rhsDate
            }
        }
    }
}
