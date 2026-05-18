import AVFoundation
import AudioToolbox
import SwiftData

final class TTSPlaylistAudioExportService {
    private let renderer: TTSPlaylistAudioExportRenderer

    init(modelContext: ModelContext) {
        self.renderer = TTSPlaylistAudioExportRenderer(modelContext: modelContext)
    }

    func export(playlist: TTSPlaylist, pauseBetweenEntriesMs: Int, to outputURL: URL) async throws {
        let pcmURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-playlist-\(UUID().uuidString)")
            .appendingPathExtension("caf")

        try? FileManager.default.removeItem(at: pcmURL)
        var didSucceed = false
        defer {
            if !didSucceed {
                try? FileManager.default.removeItem(at: outputURL)
            }
            try? FileManager.default.removeItem(at: pcmURL)
        }

        let renderedAudio = try await renderer.render(
            playlist: playlist,
            pauseBetweenEntriesMs: pauseBetweenEntriesMs,
            to: pcmURL
        )

        guard renderedAudio else {
            throw TTSPlaylistAudioExportError.noRenderableAudio
        }

        try Task.checkCancellation()
        try removeItemIfNeeded(at: outputURL)

        do {
            try await transcodePCMToM4A(inputURL: pcmURL, outputURL: outputURL)
            didSucceed = true
        } catch {
            try? removeItemIfNeeded(at: outputURL)
            throw error
        }
    }

    private func transcodePCMToM4A(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TTSPlaylistAudioExportError.invalidAudioBuffer
        }

        try await exportSession.export(to: outputURL, as: .m4a)
    }

    private func removeItemIfNeeded(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }
}
