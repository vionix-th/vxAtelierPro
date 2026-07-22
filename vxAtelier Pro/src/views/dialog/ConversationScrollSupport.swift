import SwiftData
import SwiftUI

enum ConversationScrollTarget: Hashable {
    case message(PersistentIdentifier)
    case bottom
}

enum ConversationFollowMode: Equatable {
    case following
    case detached
    case navigating(UUID)
}

struct ConversationScrollState {
    private(set) var mode: ConversationFollowMode = .following
    private(set) var hasNewContent = false
    private(set) var viewportHeight: CGFloat = 0
    private(set) var bottomPosition: CGFloat = 0

    var isFollowingLatest: Bool {
        mode == .following
    }

    var showsJumpToLatest: Bool {
        mode == .detached && hasNewContent
    }

    mutating func visibleTargetChanged(_ target: ConversationScrollTarget?) {
        guard !isNavigating else { return }
        if target == .bottom {
            mode = .following
            hasNewContent = false
        } else if bottomDistance > ConversationScrollMetrics.nearBottomThreshold {
            mode = .detached
        }
    }

    @discardableResult
    mutating func viewportChanged(_ height: CGFloat) -> Bool {
        let didResize = abs(viewportHeight - height) > 0.5
        viewportHeight = height
        return didResize && isFollowingLatest
    }

    mutating func bottomPositionChanged(_ position: CGFloat) {
        bottomPosition = position
        guard position > 0, viewportHeight > 0, !isNavigating else { return }

        if bottomDistance <= ConversationScrollMetrics.nearBottomThreshold {
            mode = .following
            hasNewContent = false
        } else {
            mode = .detached
        }
    }

    @discardableResult
    mutating func contentPublished() -> Bool {
        if isFollowingLatest {
            return true
        }
        hasNewContent = true
        return false
    }

    func layoutChanged() -> Bool {
        isFollowingLatest
    }

    mutating func beginNavigation(_ requestID: UUID) {
        mode = .navigating(requestID)
        hasNewContent = false
    }

    mutating func finishNavigation(_ requestID: UUID, at target: ConversationScrollTarget?) {
        guard mode == .navigating(requestID) else { return }
        if target == .bottom {
            mode = .following
            hasNewContent = false
        } else {
            mode = .detached
        }
    }

    mutating func jumpToLatest() {
        mode = .following
        hasNewContent = false
    }

    private var bottomDistance: CGFloat {
        max(0, bottomPosition - viewportHeight)
    }

    private var isNavigating: Bool {
        if case .navigating = mode { return true }
        return false
    }
}

enum ConversationScrollMetrics {
    static let coordinateSpace = "ConversationTimelineScrollView"
    static let nearBottomThreshold: CGFloat = 64
    static let navigationAnimationDuration = 0.2
}

struct ConversationBottomPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ConversationViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ConversationBottomSensor: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ConversationBottomPositionPreferenceKey.self,
                value: proxy.frame(in: .named(ConversationScrollMetrics.coordinateSpace)).maxY
            )
        }
        .frame(height: 1)
        .id(ConversationScrollTarget.bottom)
    }
}

struct ConversationViewportSensor: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ConversationViewportHeightPreferenceKey.self,
                value: proxy.size.height
            )
        }
    }
}
