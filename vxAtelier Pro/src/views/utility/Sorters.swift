import Foundation

struct ConversationSorter {
    static func lastTurnTimestamp(for conversation: ConversationItem) -> Date? {
        guard let lastTurn = conversation.turns.max(by: { $0.sequenceNumber < $1.sequenceNumber }) else {
            return nil
        }
        let lastEventTimestamp = lastTurn.events.map(\.message.timestamp).max()
        return max(lastTurn.userMessage.timestamp, lastEventTimestamp ?? lastTurn.userMessage.timestamp)
    }

    static func sort(
        _ conversations: [ConversationItem],
        descending: Bool,
        sortType: SidebarSortType
    ) -> [ConversationItem] {
        sortItems(
            conversations,
            descending: descending,
            sortType: sortType,
            name: { $0.title },
            timestamp: { $0.timestamp },
            lastMessage: { lastTurnTimestamp(for: $0) }
        )
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
        sortItems(
            projects,
            descending: descending,
            sortType: sortType,
            name: { $0.name },
            timestamp: { $0.timestamp },
            lastMessage: { lastTurnTimestamp(for: $0) }
        )
    }
}

private func sortItems<Item>(
    _ items: [Item],
    descending: Bool,
    sortType: SidebarSortType,
    name: (Item) -> String,
    timestamp: (Item) -> Date,
    lastMessage: (Item) -> Date?
) -> [Item] {
    switch sortType {
    case .conversationDate:
        return items.sorted {
            let lhsDate = timestamp($0)
            let rhsDate = timestamp($1)
            if lhsDate != rhsDate {
                return descending ? lhsDate > rhsDate : lhsDate < rhsDate
            }
            let comparison = name($0).localizedCaseInsensitiveCompare(name($1))
            if comparison == .orderedSame { return false }
            return descending ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    case .lastMessageDate:
        return items.sorted {
            let lhsDate = lastMessage($0) ?? timestamp($0)
            let rhsDate = lastMessage($1) ?? timestamp($1)
            if lhsDate != rhsDate {
                return descending ? lhsDate > rhsDate : lhsDate < rhsDate
            }
            let comparison = name($0).localizedCaseInsensitiveCompare(name($1))
            if comparison == .orderedSame { return false }
            return descending ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    case .alphabetically:
        return items.sorted {
            let comparison = name($0).localizedCaseInsensitiveCompare(name($1))
            if comparison == .orderedSame {
                let lhsDate = timestamp($0)
                let rhsDate = timestamp($1)
                if lhsDate == rhsDate { return false }
                return descending ? lhsDate > rhsDate : lhsDate < rhsDate
            }
            return descending ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    }
}
