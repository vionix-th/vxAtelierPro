import SwiftData
import SwiftUI

struct ConversationTimelineView: View {
    let presentation: ConversationPresentationSnapshot
    let playlists: [ConversationPlaylistSnapshot]
    let draftStore: ConversationDraftStore
    let scrollRequest: ConversationScrollRequest?
    let isSelecting: Bool
    let selectedMessageIDs: Set<PersistentIdentifier>
    let onSelect: (PersistentIdentifier) -> Void
    let onMessageTap: (PersistentIdentifier) -> Void
    let onMessageAction: (ConversationMessageAction, ConversationMessageReference) -> Void
    let onConsumeScrollRequest: (UUID) -> Void

    @State private var position: ConversationScrollTarget? = .bottom
    @State private var scrollState = ConversationScrollState()
    @State private var navigationSettlementTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(presentation.rows) { row in
                        ConversationMessageRow(
                            snapshot: row,
                            style: presentation.style,
                            playlists: playlists,
                            isSelecting: isSelecting,
                            isSelected: selectedMessageIDs.contains(row.reference.messageID),
                            onSelect: { onSelect(row.reference.messageID) },
                            onTap: { onMessageTap(row.reference.messageID) },
                            onAction: { onMessageAction($0, row.reference) },
                            onLayoutChange: { handleLayoutChange() }
                        )
                        .id(row.id)
                    }

                    StreamingAssistantRow(
                        conversationID: presentation.conversationID,
                        presentation: presentation.stream,
                        style: presentation.style,
                        draftStore: draftStore,
                        onContentPublished: { handleContentPublished(animated: false) }
                    )

                    ConversationBottomSensor()
                }
                .scrollTargetLayout()
                .padding(.vertical, AppDefaults.paddingSmall)
            }
            .coordinateSpace(name: ConversationScrollMetrics.coordinateSpace)
            .background(ConversationViewportSensor())
            .defaultScrollAnchor(.bottom)
            .scrollPosition(id: $position, anchor: .bottom)
            .onPreferenceChange(ConversationViewportHeightPreferenceKey.self) { height in
                if scrollState.viewportChanged(height) {
                    scroll(to: .bottom, animated: false)
                }
            }
            .onPreferenceChange(ConversationBottomPositionPreferenceKey.self) { bottomPosition in
                scrollState.bottomPositionChanged(bottomPosition)
            }
            .onChange(of: position) { _, target in
                scrollState.visibleTargetChanged(target)
            }
            .onChange(of: presentation.revision) { oldRevision, newRevision in
                guard oldRevision != newRevision else { return }
                let addedTurn = newRevision.turnIDs.count > oldRevision.turnIDs.count
                handleContentPublished(animated: addedTurn)
            }
            .onChange(of: scrollRequest?.requestID) { _, _ in
                handleScrollRequest(animated: true)
            }

            if scrollState.showsJumpToLatest {
                Button {
                    scrollState.jumpToLatest()
                    scroll(to: .bottom, animated: true)
                } label: {
                    Label("Jump to Latest", systemImage: "arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .padding(AppDefaults.paddingMedium)
            }
        }
        .onAppear {
            if !handleScrollRequest(animated: false) {
                scrollState.jumpToLatest()
                scroll(to: .bottom, animated: false)
            }
        }
        .onDisappear {
            navigationSettlementTask?.cancel()
        }
    }

    private func handleContentPublished(animated: Bool) {
        guard scrollState.contentPublished() else { return }
        scroll(to: .bottom, animated: animated)
    }

    private func handleLayoutChange() {
        guard scrollState.layoutChanged() else { return }
        scroll(to: .bottom, animated: false)
    }

    @discardableResult
    private func handleScrollRequest(animated: Bool) -> Bool {
        guard let request = scrollRequest,
              request.conversationID == presentation.conversationID else {
            return false
        }

        navigationSettlementTask?.cancel()
        scrollState.beginNavigation(request.requestID)
        onConsumeScrollRequest(request.requestID)
        let target = ConversationScrollTarget.message(request.messageID)
        scroll(to: target, animated: animated)

        navigationSettlementTask = Task { @MainActor in
            if animated {
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        (ConversationScrollMetrics.navigationAnimationDuration + 0.05)
                            * 1_000_000_000
                    )
                )
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            scrollState.finishNavigation(request.requestID, at: position)
        }
        return true
    }

    private func scroll(to target: ConversationScrollTarget, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: ConversationScrollMetrics.navigationAnimationDuration)) {
                position = target
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                position = target
            }
        }
    }
}
