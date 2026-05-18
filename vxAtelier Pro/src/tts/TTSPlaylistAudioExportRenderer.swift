import AVFoundation
import AudioToolbox
import NaturalLanguage
import SwiftData

enum TTSPlaylistAudioExportError: LocalizedError {
    case emptyPlaylist
    case noRenderableAudio
    case invalidAudioBuffer

    var errorDescription: String? {
        switch self {
        case .emptyPlaylist:
            return "The playlist is empty."
        case .noRenderableAudio:
            return "The playlist does not contain renderable speech."
        case .invalidAudioBuffer:
            return "The speech synthesizer returned an invalid audio buffer."
        }
    }
}

final class TTSPlaylistAudioExportRenderer {
    private final class RenderState {
        var audioFile: AVAudioFile?
        var audioConverter: AVAudioConverter?
        var hasWrittenAudio = false
    }

    private let modelContext: ModelContext
    private let synthesizer = AVSpeechSynthesizer()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func render(
        playlist: TTSPlaylist,
        pauseBetweenEntriesMs: Int,
        to pcmURL: URL
    ) async throws -> Bool {
        let entries = playlist.orderedEntries
        guard !entries.isEmpty else {
            throw TTSPlaylistAudioExportError.emptyPlaylist
        }

        let state = RenderState()

        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let renderedAudio = try await render(entry: entry, to: pcmURL, state: state)

            if renderedAudio, index < entries.count - 1, pauseBetweenEntriesMs > 0 {
                try appendSilence(milliseconds: pauseBetweenEntriesMs, to: state)
            }
        }

        guard state.hasWrittenAudio else {
            throw TTSPlaylistAudioExportError.noRenderableAudio
        }

        return state.hasWrittenAudio
    }

    private func render(entry: TTSPlaylistEntry, to url: URL, state: RenderState) async throws -> Bool {
        let segments = segmentText(entry.text)
        guard !segments.isEmpty else {
            return false
        }

        var renderedAudio = false
        for segment in segments {
            try Task.checkCancellation()
            let utterance = configuredUtterance(for: segment, role: entry.role)
            try await write(utterance, to: url, state: state)
            renderedAudio = true
        }

        return renderedAudio
    }

    private func write(_ utterance: AVSpeechUtterance, to url: URL, state: RenderState) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false

            synthesizer.write(utterance) { buffer in
                if resumed {
                    return
                }

                if Task.isCancelled {
                    resumed = true
                    self.synthesizer.stopSpeaking(at: .immediate)
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    resumed = true
                    continuation.resume(throwing: TTSPlaylistAudioExportError.invalidAudioBuffer)
                    return
                }

                do {
                    if pcmBuffer.frameLength == 0 {
                        resumed = true
                        continuation.resume(returning: ())
                        return
                    }

                    if state.audioFile == nil {
                        let outputFormat = try self.makePCMFormat(from: pcmBuffer.format)
                        state.audioFile = try self.makePCMFile(for: url, outputFormat: outputFormat)
                        state.audioConverter = AVAudioConverter(from: pcmBuffer.format, to: outputFormat)
                    }

                    guard let audioFile = state.audioFile else {
                        throw TTSPlaylistAudioExportError.invalidAudioBuffer
                    }

                    if let converter = state.audioConverter,
                       pcmBuffer.format != audioFile.processingFormat {
                        try self.write(converting: pcmBuffer, with: converter, to: audioFile)
                    } else {
                        try audioFile.write(from: pcmBuffer)
                    }

                    state.hasWrittenAudio = true
                } catch {
                    resumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func appendSilence(milliseconds: Int, to state: RenderState) throws {
        guard milliseconds > 0, let audioFile = state.audioFile else {
            return
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * Double(milliseconds) / 1000.0)
        guard frameCount > 0 else {
            return
        }

        guard let silence = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw TTSPlaylistAudioExportError.invalidAudioBuffer
        }

        silence.frameLength = frameCount

        if let floatChannelData = silence.floatChannelData {
            for channel in 0..<Int(audioFile.processingFormat.channelCount) {
                floatChannelData[channel].initialize(repeating: 0, count: Int(frameCount))
            }
        } else if let int16ChannelData = silence.int16ChannelData {
            for channel in 0..<Int(audioFile.processingFormat.channelCount) {
                int16ChannelData[channel].initialize(repeating: 0, count: Int(frameCount))
            }
        }

        try audioFile.write(from: silence)
    }

    private func configuredUtterance(for segment: TTSSegment, role: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: segment.text)
        let (voice, config) = resolveVoice(for: segment, role: role)
        utterance.voice = voice

        if let config {
            utterance.rate = Float(config.speechRate)
            utterance.pitchMultiplier = Float(config.pitchMultiplier)
        } else {
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
        }

        return utterance
    }

    private func resolveVoice(for segment: TTSSegment, role: String) -> (voice: AVSpeechSynthesisVoice, config: VoiceConfigurationItem?) {
        let config = voiceConfiguration(for: role, language: segment.language)

        if let config,
           !config.voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: config.voiceIdentifier) {
            return (voice, config)
        }

        if let voice = AVSpeechSynthesisVoice(language: segment.language) {
            return (voice, config)
        }

        if let englishVoice = AVSpeechSynthesisVoice(language: "en") {
            return (englishVoice, nil)
        }

        return (AVSpeechSynthesisVoice.speechVoices().first ?? AVSpeechSynthesisVoice(language: "en-US")!, nil)
    }

    private func voiceConfiguration(for role: String, language: String) -> VoiceConfigurationItem? {
        do {
            let baseLanguage = baseLanguageCode(language)
            let descriptor = FetchDescriptor<VoiceConfigurationItem>()
            let configs = try modelContext.fetch(descriptor)

            if let config = configs.first(where: {
                $0.role == role && $0.language.caseInsensitiveCompare(language) == .orderedSame
            }) {
                return config
            }

            return configs.first(where: {
                $0.role == role && baseLanguageCode($0.language) == baseLanguage
            })
        } catch {
            vxAtelierPro.log.error("❌ Failed to fetch voice configurations for export - \(error.localizedDescription)")
            return nil
        }
    }

    private func baseLanguageCode(_ languageCode: String) -> String {
        languageCode.split(separator: "-").first.map(String.init) ?? languageCode
    }

    private func detectLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }

    private func segmentText(_ text: String) -> [TTSSegment] {
        let sentenceEndings = ".!?\n\r\t"
        let softSeparators = ",:;-"
        let quoteMarks = "\"'"

        let components = text.components(separatedBy: CharacterSet(charactersIn: sentenceEndings))
            .flatMap { sentence -> [String] in
                sentence.components(separatedBy: CharacterSet(charactersIn: softSeparators))
            }
            .map { segment -> String in
                var cleaned = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: quoteMarks))
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        return components.map { segment in
            TTSSegment(
                text: segment,
                language: detectLanguage(for: segment)
            )
        }
    }

    private func makePCMFormat(from sourceFormat: AVAudioFormat) throws -> AVAudioFormat {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: sourceFormat.channelCount,
            interleaved: false
        ) else {
            throw TTSPlaylistAudioExportError.invalidAudioBuffer
        }

        return outputFormat
    }

    private func makePCMFile(for url: URL, outputFormat: AVAudioFormat) throws -> AVAudioFile {
        try AVAudioFile(
            forWriting: url,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
    }

    private func write(converting buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to audioFile: AVAudioFile) throws {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(max(1, buffer.frameLength))
        ) else {
            throw TTSPlaylistAudioExportError.invalidAudioBuffer
        }

        var didSupplyInput = false
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if didSupplyInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            didSupplyInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            throw error
        }

        try audioFile.write(from: outputBuffer)
    }
}
