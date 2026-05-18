import AVFoundation
import NaturalLanguage
import SwiftData
import SwiftUI

struct TTSSegment {
    let text: String
    let language: String
}

enum TTSRepeatMode: String {
    case none
    case one
    case all
}

@Observable
final class TTSQueue: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let modelContext: ModelContext
    private var synthesizer: AVSpeechSynthesizer!
    private var isManualSelection = false
    private var suppressCompletionHandling = false
    private var pendingAdvanceWorkItem: DispatchWorkItem?
    private var currentSegments: [TTSSegment] = []
    private var currentSegmentIndex = 0
    private let activePlaylistStorageKey = AppSettings.Keys.ttsActivePlaylistID

    var isPlaying = false
    var currentIndex = 0
    var activePlaylistID: PersistentIdentifier?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        vxAtelierPro.log.debug("🔊 TTS queue initialized")
    }

    private func getSynthesizer() -> AVSpeechSynthesizer {
        if synthesizer == nil {
            synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
            vxAtelierPro.log.debug("🔊 Speech synthesizer initialized")
        }
        return synthesizer
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            vxAtelierPro.log.error("❌ Failed to save TTS context - \(error.localizedDescription)")
        }
    }

    private func loadPersistedActivePlaylistID() -> PersistentIdentifier? {
        guard let data = UserDefaults.standard.data(forKey: activePlaylistStorageKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(PersistentIdentifier.self, from: data)
        } catch {
            vxAtelierPro.log.error("❌ Failed to decode persisted TTS playlist identifier - \(error.localizedDescription)")
            return nil
        }
    }

    private func persistActivePlaylistID(_ id: PersistentIdentifier?) {
        let defaults = UserDefaults.standard

        guard let id else {
            defaults.removeObject(forKey: activePlaylistStorageKey)
            return
        }

        do {
            let data = try JSONEncoder().encode(id)
            defaults.set(data, forKey: activePlaylistStorageKey)
        } catch {
            vxAtelierPro.log.error("❌ Failed to encode persisted TTS playlist identifier - \(error.localizedDescription)")
        }
    }

    private func restorePersistedActivePlaylistIfNeeded() {
        guard activePlaylistID == nil else { return }
        guard let persistedID = loadPersistedActivePlaylistID() else { return }
        activePlaylistID = persistedID
    }

    private func cancelPendingAdvance() {
        pendingAdvanceWorkItem?.cancel()
        pendingAdvanceWorkItem = nil
    }

    private func fetchPlaylist(with id: PersistentIdentifier) -> TTSPlaylist? {
        var descriptor = FetchDescriptor<TTSPlaylist>(sortBy: [])
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate { $0.id == id }
        return try? modelContext.fetch(descriptor).first
    }

    private func orderedPlaylists() -> [TTSPlaylist] {
        let descriptor = FetchDescriptor<TTSPlaylist>(
            sortBy: [
                SortDescriptor(\TTSPlaylist.updatedAt, order: .reverse),
                SortDescriptor(\TTSPlaylist.createdAt, order: .reverse)
            ]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func activePlaylist(createIfNeeded: Bool = false, preferredName: String? = nil) -> TTSPlaylist? {
        restorePersistedActivePlaylistIfNeeded()

        if let activePlaylistID, let playlist = fetchPlaylist(with: activePlaylistID) {
            return playlist
        }

        if let first = orderedPlaylists().first {
            activePlaylistID = first.id
            persistActivePlaylistID(first.id)
            currentIndex = 0
            return first
        }

        guard createIfNeeded else { return nil }
        let playlistName = preferredName ?? defaultPlaylistName
        return createPlaylist(named: playlistName)
    }

    private func activePlaylistForAdding(preferredName: String? = nil) -> TTSPlaylist? {
        restorePersistedActivePlaylistIfNeeded()

        if let activePlaylistID, let playlist = fetchPlaylist(with: activePlaylistID) {
            return playlist
        }

        let playlistName = preferredName ?? defaultPlaylistName
        return createPlaylist(named: playlistName)
    }

    private var defaultPlaylistName: String {
        let base = "Playlist"
        let existing = Set(orderedPlaylists().map(\.name))
        guard !existing.contains(base) else {
            var suffix = 2
            while existing.contains("\(base) \(suffix)") {
                suffix += 1
            }
            return "\(base) \(suffix)"
        }
        return base
    }

    private func uniquePlaylistName(_ rawName: String, excluding playlistID: PersistentIdentifier? = nil) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? defaultPlaylistName : trimmedName
        let existing = Set(
            orderedPlaylists()
                .filter { $0.id != playlistID }
                .map(\.name)
        )

        guard !existing.contains(baseName) else {
            var suffix = 2
            while existing.contains("\(baseName) \(suffix)") {
                suffix += 1
            }
            return "\(baseName) \(suffix)"
        }

        return baseName
    }

    private func notifyPlaylistMutation(_ playlist: TTSPlaylist) {
        playlist.updatedAt = Date()
        saveContext()
    }

    private func selectPlaylist(_ playlist: TTSPlaylist?) {
        cancelPendingAdvance()
        if let playlist {
            activePlaylistID = playlist.id
            persistActivePlaylistID(playlist.id)
            currentIndex = min(currentIndex, max(0, playlist.orderedEntries.count - 1))
        } else {
            activePlaylistID = nil
            persistActivePlaylistID(nil)
            currentIndex = 0
        }
        currentSegments = []
        currentSegmentIndex = 0
    }

    private func baseLanguageCode(_ languageCode: String) -> String {
        languageCode.split(separator: "-").first.map(String.init) ?? languageCode
    }

    private func getVoiceConfiguration(for role: String, language: String) -> VoiceConfigurationItem? {
        do {
            let baseLanguage = baseLanguageCode(language)
            let descriptor = FetchDescriptor<VoiceConfigurationItem>()
            let configs = try modelContext.fetch(descriptor)

            if let config = configs.first(where: {
                $0.role == role && $0.language.caseInsensitiveCompare(language) == .orderedSame
            }) {
                vxAtelierPro.log.debug("🎤 Found exact voice configuration for role '\(role)' and language '\(language)'")
                return config
            }

            if let config = configs.first(where: {
                $0.role == role && baseLanguageCode($0.language) == baseLanguage
            }) {
                vxAtelierPro.log.debug("🎤 Found role-matched voice configuration for role '\(role)' and base language '\(baseLanguage)'")
                return config
            }

            vxAtelierPro.log.warning("⚠️ No voice configuration found for role '\(role)' and language '\(language)'")
            return nil
        } catch {
            vxAtelierPro.log.error("❌ Failed to fetch voice configurations - \(error.localizedDescription)")
            return nil
        }
    }

    private func getVoiceForSegment(_ segment: TTSSegment, role: String) -> (voice: AVSpeechSynthesisVoice, config: VoiceConfigurationItem?) {
        let config = getVoiceConfiguration(for: role, language: segment.language)

        if let config,
           !config.voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: config.voiceIdentifier) {
            vxAtelierPro.log.debug("🎤 Using configured voice '\(voice.name)' for role '\(role)' and language '\(segment.language)'")
            return (voice, config)
        }

        if let defaultVoice = AVSpeechSynthesisVoice(language: segment.language) {
            if config == nil {
                vxAtelierPro.log.debug("🎤 Using system default voice for role '\(role)' and language '\(segment.language)'")
            } else {
                vxAtelierPro.log.debug("🎤 Using system default voice for configured role '\(role)' and language '\(segment.language)'")
            }
            return (defaultVoice, config)
        }

        guard let englishVoice = AVSpeechSynthesisVoice(language: "en") else {
            vxAtelierPro.log.error("❌ Critical - No English fallback voice available")
            return (AVSpeechSynthesisVoice.speechVoices().first ?? AVSpeechSynthesisVoice(language: "en-US")!, nil)
        }

        return (englishVoice, nil)
    }

    private func detectLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage?.rawValue {
            return language
        }
        vxAtelierPro.log.warning("⚠️ Language detection failed for text, falling back to English")
        return "en"
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

        var segments: [TTSSegment] = []
        var currentLanguage: String?
        var currentText = ""

        for component in components {
            let language = detectLanguage(for: component)

            if component.count < 15, let current = currentLanguage, language == current {
                if !currentText.isEmpty {
                    currentText += ", "
                }
                currentText += component
                continue
            }

            if !currentText.isEmpty, let currentLanguage {
                segments.append(TTSSegment(text: currentText, language: currentLanguage))
            }

            currentText = component
            currentLanguage = language
        }

        if !currentText.isEmpty, let currentLanguage {
            segments.append(TTSSegment(text: currentText, language: currentLanguage))
        }

        return segments
    }

    private func startSpeaking(text: String, role: String) {
        cancelPendingAdvance()
        currentSegments = segmentText(text)
        currentSegmentIndex = 0

        guard !currentSegments.isEmpty else {
            isPlaying = false
            return
        }

        speakNextSegment(role: role)
        vxAtelierPro.log.debug("🗣️ Speaking \(role) message with \(currentSegments.count) segments")
    }

    private func speakNextSegment(role: String) {
        guard currentSegmentIndex < currentSegments.count else {
            currentSegments = []
            currentSegmentIndex = 0
            return
        }

        let segment = currentSegments[currentSegmentIndex]
        let utterance = AVSpeechUtterance(string: segment.text)
        let (voice, config) = getVoiceForSegment(segment, role: role)
        utterance.voice = voice

        if let config {
            utterance.rate = Float(config.speechRate)
            utterance.pitchMultiplier = Float(config.pitchMultiplier)
            vxAtelierPro.log.debug("🎤 Using speech rate: \(config.speechRate), pitch: \(config.pitchMultiplier)")
        } else {
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
            vxAtelierPro.log.debug("🎤 Using default speech rate: 0.5, pitch: 1.0")
        }

        vxAtelierPro.log.debug("🗣️ Speaking segment \(currentSegmentIndex + 1)/\(currentSegments.count) in language '\(segment.language)'")
        getSynthesizer().speak(utterance)
    }

    private func orderedEntries(in playlist: TTSPlaylist?) -> [TTSPlaylistEntry] {
        playlist?.orderedEntries ?? []
    }

    var currentItem: TTSPlaylistEntry? {
        guard let playlist = currentPlaylist else {
            return nil
        }
        let entries = playlist.orderedEntries
        guard !entries.isEmpty else {
            return nil
        }
        if currentIndex >= entries.count {
            currentIndex = entries.count - 1
        }
        return entries[currentIndex]
    }

    func createPlaylist(named name: String) -> TTSPlaylist? {
        let resolvedName = uniquePlaylistName(name)
        let playlist = TTSPlaylist(name: resolvedName)
        modelContext.insert(playlist)
        saveContext()
        selectPlaylist(playlist)
        return playlist
    }

    func renamePlaylist(id: PersistentIdentifier, to name: String) {
        guard let playlist = fetchPlaylist(with: id) else { return }
        let resolvedName = uniquePlaylistName(name, excluding: id)
        guard playlist.name != resolvedName else { return }
        playlist.name = resolvedName
        notifyPlaylistMutation(playlist)
    }

    func deletePlaylist(id: PersistentIdentifier) {
        guard let playlist = fetchPlaylist(with: id) else { return }
        let wasActive = activePlaylistID == id
        stop()
        modelContext.delete(playlist)
        saveContext()
        if wasActive {
            selectPlaylist(id: orderedPlaylists().first?.id)
        }
    }

    func selectPlaylist(id: PersistentIdentifier?) {
        if activePlaylistID == id {
            return
        }

        stop()

        if let id, let playlist = fetchPlaylist(with: id) {
            selectPlaylist(playlist)
            currentIndex = 0
        } else {
            selectPlaylist(nil)
        }
    }

    func selectFirstPlaylistIfNeeded() {
        restorePersistedActivePlaylistIfNeeded()
        guard activePlaylistID == nil else { return }
        if let first = orderedPlaylists().first {
            selectPlaylist(id: first.id)
        }
    }

    func add(_ message: MessageItem, conversationID: PersistentIdentifier, createPlaylistNamed playlistName: String? = nil) {
        addEntry(
            role: message.role,
            text: message.displayText,
            sourceConversationIDString: String(describing: conversationID),
            sourceMessageIDString: String(describing: message.id),
            createPlaylistNamed: playlistName
        )
    }

    func add(_ messages: [MessageItem], conversationID: PersistentIdentifier, createPlaylistNamed playlistName: String? = nil) {
        guard !messages.isEmpty else { return }
        let playlist = activePlaylistForAdding(preferredName: playlistName)
        guard let playlist else { return }

        for message in messages {
            let entry = TTSPlaylistEntry(
                orderIndex: playlist.nextOrderIndex(),
                role: message.role,
                text: message.displayText,
                sourceConversationIDString: String(describing: conversationID),
                sourceMessageIDString: String(describing: message.id),
                playlist: playlist
            )
            playlist.entries.append(entry)
        }

        playlist.normalizeEntryOrder()
        saveContext()
    }

    func addCustomEntry(text: String, role: String, createPlaylistNamed playlistName: String? = nil) {
        addEntry(
            role: role,
            text: text,
            sourceConversationIDString: nil,
            sourceMessageIDString: nil,
            createPlaylistNamed: playlistName
        )
    }

    private func addEntry(
        role: String,
        text: String,
        sourceConversationIDString: String?,
        sourceMessageIDString: String?,
        createPlaylistNamed playlistName: String? = nil
    ) {
        let playlist = activePlaylistForAdding(preferredName: playlistName)
        guard let playlist else { return }

        let entry = TTSPlaylistEntry(
            orderIndex: playlist.nextOrderIndex(),
            role: role,
            text: text,
            sourceConversationIDString: sourceConversationIDString,
            sourceMessageIDString: sourceMessageIDString,
            playlist: playlist
        )
        playlist.entries.append(entry)
        notifyPlaylistMutation(playlist)
    }

    func read(_ message: MessageItem) {
        stop()
        isManualSelection = true
        startSpeaking(text: message.displayText, role: message.role)
    }

    func play() {
        guard let playlist = activePlaylist(createIfNeeded: false) else { return }
        let entries = orderedEntries(in: playlist)
        guard !entries.isEmpty else {
            currentIndex = 0
            return
        }

        if currentIndex >= entries.count {
            currentIndex = 0
        }

        if !getSynthesizer().isSpeaking || getSynthesizer().isPaused {
            startSpeaking(text: entries[currentIndex].text, role: entries[currentIndex].role)
        }
    }

    func jumpTo(_ index: Int) {
        jumpTo(index, manualSelection: false)
    }

    func jumpTo(_ index: Int, manualSelection: Bool) {
        guard let playlist = activePlaylist(createIfNeeded: false) else { return }
        let entries = orderedEntries(in: playlist)
        guard index >= 0 && index < entries.count else {
            vxAtelierPro.log.error("❌ Invalid jump index \(index)")
            return
        }

        isManualSelection = manualSelection
        if getSynthesizer().isSpeaking || getSynthesizer().isPaused {
            suppressCompletionHandling = true
            getSynthesizer().stopSpeaking(at: .immediate)
        }

        currentIndex = index
        startSpeaking(text: entries[index].text, role: entries[index].role)
    }

    func pause() {
        getSynthesizer().pauseSpeaking(at: .immediate)
        isPlaying = false
        vxAtelierPro.log.debug("⏸️ Playback paused")
    }

    func resume() {
        if !isPlaying {
            if getSynthesizer().isPaused {
                getSynthesizer().continueSpeaking()
                isPlaying = true
                vxAtelierPro.log.debug("▶️ Playback resumed from pause")
            } else {
                vxAtelierPro.log.debug("▶️ Starting new playback")
                play()
            }
        }
    }

    func stop() {
        cancelPendingAdvance()
        if getSynthesizer().isSpeaking || getSynthesizer().isPaused {
            suppressCompletionHandling = true
            getSynthesizer().stopSpeaking(at: .immediate)
        }
        isPlaying = false
        currentSegments = []
        currentSegmentIndex = 0
        vxAtelierPro.log.debug("⏹️ Playback stopped")
    }

    func next() {
        guard let playlist = activePlaylist(createIfNeeded: false) else { return }
        let entries = orderedEntries(in: playlist)
        guard !entries.isEmpty else {
            vxAtelierPro.log.debug("⏭️ Cannot move to next - playlist is empty")
            return
        }

        if currentIndex < entries.count - 1 {
            vxAtelierPro.log.debug("⏭️ Moving to next item (\(currentIndex + 2)/\(entries.count))")
            jumpTo(currentIndex + 1, manualSelection: false)
        } else {
            let repeatMode = UserDefaults.standard.string(forKey: AppSettings.Keys.ttsRepeatMode) ?? AppDefaults.ttsRepeatMode
            if repeatMode == "all" {
                vxAtelierPro.log.debug("🔄 Wrapping to start (repeat all mode)")
                jumpTo(0, manualSelection: false)
            } else {
                vxAtelierPro.log.debug("⏭️ Cannot move to next - already at end of \(entries.count)")
            }
        }
    }

    func previous() {
        guard let playlist = activePlaylist(createIfNeeded: false) else { return }
        let entries = orderedEntries(in: playlist)
        guard !entries.isEmpty else {
            vxAtelierPro.log.debug("⏮️ Cannot move to previous - playlist is empty")
            return
        }

        if currentIndex > 0 {
            vxAtelierPro.log.debug("⏮️ Moving to previous item (\(currentIndex)/\(entries.count))")
            jumpTo(currentIndex - 1, manualSelection: false)
        } else {
            let repeatMode = UserDefaults.standard.string(forKey: AppSettings.Keys.ttsRepeatMode) ?? AppDefaults.ttsRepeatMode
            if repeatMode == "all" {
                vxAtelierPro.log.debug("🔁 Wrapping to end (repeat all mode)")
                jumpTo(entries.count - 1, manualSelection: false)
            } else {
                vxAtelierPro.log.debug("⏮️ Cannot move to previous - already at start of playlist")
            }
        }
    }

    func remove(at index: Int) {
        guard let playlist = activePlaylist(createIfNeeded: false) else { return }
        let entries = orderedEntries(in: playlist)
        guard index >= 0 && index < entries.count else {
            vxAtelierPro.log.error("❌ Invalid remove index \(index)")
            return
        }

        let wasPlaying = isPlaying
        let removedEntryID = entries[index].id

        if index == currentIndex {
            stop()
        }

        playlist.entries.removeAll { $0.id == removedEntryID }
        playlist.normalizeEntryOrder()
        saveContext()

        let updatedEntries = orderedEntries(in: playlist)
        if updatedEntries.isEmpty {
            currentIndex = 0
        } else if index < updatedEntries.count {
            currentIndex = index
            if wasPlaying {
                startSpeaking(text: updatedEntries[index].text, role: updatedEntries[index].role)
            }
        } else {
            currentIndex = updatedEntries.count - 1
        }

        vxAtelierPro.log.debug("🗑️ Removed item at index \(index), playlist now has \(updatedEntries.count) items")
    }

    func moveEntries(from source: IndexSet, to destination: Int) {
        guard let playlist = activePlaylist(createIfNeeded: false) else { return }
        let entries = orderedEntries(in: playlist)
        guard !source.isEmpty else { return }
        guard source.allSatisfy({ $0 >= 0 && $0 < entries.count }) else {
            vxAtelierPro.log.error("❌ Invalid reorder source indexes: \(source)")
            return
        }

        let currentEntryID = currentItem?.id
        var reorderedEntries = entries
        reorderedEntries.move(fromOffsets: source, toOffset: destination)

        for (index, entry) in reorderedEntries.enumerated() {
            entry.orderIndex = index
        }

        playlist.updatedAt = Date()
        saveContext()

        if let currentEntryID,
           let currentPosition = reorderedEntries.firstIndex(where: { $0.id == currentEntryID }) {
            currentIndex = currentPosition
        } else {
            currentIndex = min(currentIndex, max(0, reorderedEntries.count - 1))
        }

        vxAtelierPro.log.debug("↕️ Reordered \(source.count) playlist item(s)")
    }

    func clear() {
        stop()
        if let playlist = activePlaylist(createIfNeeded: false) {
            playlist.entries.removeAll()
            playlist.updatedAt = Date()
            saveContext()
        }
        currentIndex = 0
    }

    func playlistEntries(for playlistID: PersistentIdentifier? = nil) -> [TTSPlaylistEntry] {
        if let playlistID, let playlist = fetchPlaylist(with: playlistID) {
            return orderedEntries(in: playlist)
        }
        return orderedEntries(in: activePlaylist())
    }

    func playlist(with id: PersistentIdentifier?) -> TTSPlaylist? {
        guard let id else { return nil }
        return fetchPlaylist(with: id)
    }

    func playPlaylist(id: PersistentIdentifier) {
        guard let playlist = fetchPlaylist(with: id) else { return }
        stop()
        selectPlaylist(playlist)
        currentIndex = 0
        play()
    }

    func hasPlaylists() -> Bool {
        !orderedPlaylists().isEmpty
    }

    func playlistCount() -> Int {
        orderedPlaylists().count
    }

    func currentPlaylistName() -> String? {
        currentPlaylist?.name
    }

    func currentPlaylistID() -> PersistentIdentifier? {
        activePlaylistID ?? loadPersistedActivePlaylistID()
    }

    func currentPlaylistEntryCount() -> Int {
        currentPlaylist?.orderedEntries.count ?? 0
    }

    func currentPlaylistHasEntries() -> Bool {
        currentPlaylistEntryCount() > 0
    }

    func currentPlaylistOrderedEntries() -> [TTSPlaylistEntry] {
        currentPlaylist?.orderedEntries ?? []
    }

    func playlists() -> [TTSPlaylist] {
        orderedPlaylists()
    }

    func reloadSelectionIfNeeded() {
        restorePersistedActivePlaylistIfNeeded()
        if let activePlaylistID, fetchPlaylist(with: activePlaylistID) == nil {
            selectPlaylist(orderedPlaylists().first)
        }
    }

    func selectPlaylistByIndex(_ index: Int) {
        let playlists = orderedPlaylists()
        guard index >= 0 && index < playlists.count else { return }
        selectPlaylist(playlists[index])
    }

    func updateActivePlaylistTimestamp() {
        guard let playlist = activePlaylist(createIfNeeded: false) else { return }
        playlist.updatedAt = Date()
        saveContext()
    }

    private var currentPlaylist: TTSPlaylist? {
        if let activePlaylistID {
            return fetchPlaylist(with: activePlaylistID)
        }

        if let persistedID = loadPersistedActivePlaylistID() {
            return fetchPlaylist(with: persistedID)
        }

        return nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [self] in
            self.isPlaying = true
            if self.currentSegments.count > 1 {
                vxAtelierPro.log.debug("▶️ Started speaking segment \(self.currentSegmentIndex + 1)/\(self.currentSegments.count) of message \(self.currentIndex + 1)")
            } else {
                vxAtelierPro.log.debug("▶️ Started speaking message \(self.currentIndex + 1)")
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [self] in
            if self.suppressCompletionHandling {
                self.suppressCompletionHandling = false
                self.currentSegments = []
                self.currentSegmentIndex = 0
                self.isPlaying = false
                return
            }

            if !self.currentSegments.isEmpty && self.currentSegmentIndex < self.currentSegments.count - 1 {
                self.currentSegmentIndex += 1
                if let current = self.currentItem {
                    if self.currentSegments.count > 1 {
                        vxAtelierPro.log.debug("➡️ Moving to next segment (\(self.currentSegmentIndex + 1)/\(self.currentSegments.count))")
                    }
                    self.speakNextSegment(role: current.role)
                }
                return
            }

            let pauseMs = UserDefaults.standard.integer(forKey: AppSettings.Keys.ttsEntryPauseMs)
            let pauseSeconds = Double(max(0, pauseMs)) / 1000.0

            guard let playlist = self.activePlaylist(createIfNeeded: false) else {
                self.isPlaying = false
                return
            }

            let entries = playlist.orderedEntries
            guard !entries.isEmpty else {
                self.isPlaying = false
                return
            }

            if self.isManualSelection {
                self.isManualSelection = false
                vxAtelierPro.log.debug("👆 Manual selection playback completed")
                self.isPlaying = false
                return
            }

            let repeatMode = UserDefaults.standard.string(forKey: AppSettings.Keys.ttsRepeatMode) ?? AppDefaults.ttsRepeatMode

            let nextIndex: Int?
            if self.currentIndex < entries.count - 1 {
                nextIndex = self.currentIndex + 1
            } else {
                switch repeatMode {
                case "one":
                    nextIndex = self.currentIndex
                case "all":
                    nextIndex = 0
                default:
                    nextIndex = nil
                }
            }

            guard let nextIndex else {
                vxAtelierPro.log.debug("✅ Playback completed (no repeat)")
                self.isPlaying = false
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard let playlist = self.activePlaylist(createIfNeeded: false) else {
                    self.isPlaying = false
                    return
                }
                let entries = playlist.orderedEntries
                guard nextIndex >= 0 && nextIndex < entries.count else {
                    self.isPlaying = false
                    return
                }
                self.currentIndex = nextIndex
                vxAtelierPro.log.debug("⏭️ Advancing to item \(self.currentIndex + 1)/\(entries.count) after \(pauseMs)ms pause")
                self.startSpeaking(text: entries[nextIndex].text, role: entries[nextIndex].role)
            }
            self.pendingAdvanceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseSeconds, execute: workItem)
        }
    }
}
