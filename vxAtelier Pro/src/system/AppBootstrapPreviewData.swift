import Foundation
import SwiftData

@MainActor
enum AppBootstrapPreviewData {
    static func seedPreviewData(into context: ModelContext) {
        let apiConfiguration = APIConfigurationItem(
            name: "Preview API",
            apiKey: "preview-key",
            baseURL: "https://example.invalid",
            isDefault: true,
            defaultModel: "preview-model",
            providerID: .openAIPlatform
        )

        let previewModel = ModelItem(modelID: "preview-model", apiConfiguration: apiConfiguration)
        previewModel.displayName = "Preview Model"

        let conversationOptions = ConversationOptions(apiConfiguration: apiConfiguration)
        conversationOptions.selectedModelID = previewModel.modelID

        let project = ProjectItem(
            "Preview Project",
            defaultOptions: ConversationOptions(apiConfiguration: apiConfiguration)
        )
        let conversation = ConversationItem("Preview Conversation", options: conversationOptions)
        conversation.project = project

        let userMessage = MessageItem(role: "user", text: "Show the preview-ready settings view.")
        let turn = ConversationTurn(sequenceNumber: 0, userMessage: userMessage, conversation: conversation)
        conversation.turns.append(turn)

        context.insert(apiConfiguration)
        context.insert(previewModel)
        context.insert(project)
        context.insert(conversation)

        for playlist in previewTTSPlaylists() {
            context.insert(playlist)
        }

        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.ttsActivePlaylistID)

        do {
            try context.save()
            vxAtelierPro.log.debug("Preview data seeded")
        } catch {
            vxAtelierPro.log.error("Failed to seed preview data: \(error.localizedDescription)")
        }
    }

    private static func previewTTSPlaylists() -> [TTSPlaylist] {
        let baseDate = Date(timeIntervalSinceReferenceDate: 750_000_000)

        return [
            makePreviewTTSPlaylist(
                name: "Morning Warmup",
                createdAt: baseDate,
                updatedAt: baseDate.addingTimeInterval(120),
                entries: [
                    ("system", "Welcome back. Take one slow breath and start with the highest-priority task."),
                    ("assistant", "Priority one is clear. I will keep responses tight and actionable."),
                    ("user", "Good. Keep the next step small and concrete."),
                ]
            ),
            makePreviewTTSPlaylist(
                name: "Review Pass",
                createdAt: baseDate.addingTimeInterval(600),
                updatedAt: baseDate.addingTimeInterval(900),
                entries: [
                    ("system", "Check for missing edge cases before shipping."),
                    ("assistant", "I will verify data flow, deletion paths, and persistence assumptions."),
                    ("user", "Report any gaps in plain terms."),
                ]
            ),
        ]
    }

    private static func makePreviewTTSPlaylist(
        name: String,
        createdAt: Date,
        updatedAt: Date,
        entries: [(role: String, text: String)]
    ) -> TTSPlaylist {
        let playlist = TTSPlaylist(name: name, createdAt: createdAt, updatedAt: updatedAt)
        playlist.entries = entries.enumerated().map { index, entry in
            TTSPlaylistEntry(
                orderIndex: index,
                role: entry.role,
                text: entry.text,
                sourceConversationIDString: "preview",
                sourceMessageIDString: nil,
                playlist: playlist
            )
        }
        return playlist
    }
}
