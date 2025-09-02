import SwiftData
import SwiftUI

struct TTSControlView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TTSQueue.self) private var ttsQueue
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @AppStorage("TTSAutoplay") private var autoplay: Bool = AppDefaults.ttsAutoplay
    @AppStorage("TTSRepeatMode") private var repeatMode: String = AppDefaults.ttsRepeatMode
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Now Playing section
                if let current = ttsQueue.currentItem {
                    VStack(spacing: 12) {
                        Circle()
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
                            )
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "waveform")
                                    .font(.title)
                                    .foregroundColor(ttsQueue.isPlaying ? .accentColor : .secondary)
                            )
                            .padding(.top)

                        Text(current.context.displayString)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ScrollView {
                            Text(current.message.content.text)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                        )
                        .padding(.horizontal)
                    }
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .background(
                        colorScheme == .dark ? Color.black : Color.white
                    )
                }

                // Playlist
                List {
                    ForEach(Array(ttsQueue.playlist.enumerated()), id: \.element.message.id) {
                        index, item in
                        HStack(spacing: 12) {
                            if index == ttsQueue.currentIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.accentColor)
                            } else {
                                Text("\(item.context.messageIndex + 1)")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.context.displayString)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                HStack {
                                    Text(item.message.role.capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(
                                        item.message.timestamp.formatted(.dateTime.hour().minute())
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button(role: .destructive) {
                                ttsQueue.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from playlist")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            ttsQueue.jumpTo(index)
                        }
                    }
                    .onDelete { indexSet in
                        // Remove in descending order to avoid index shifting
                        for index in indexSet.sorted(by: >) {
                            ttsQueue.remove(at: index)
                        }
                    }
                }
                .listStyle(.plain)

                // Player Controls
                VStack(spacing: 16) {
                    // Progress indicator
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(
                                width: geometry.size.width
                                    * (Double(ttsQueue.currentIndex + 1)
                                        / Double(max(1, ttsQueue.playlist.count)))
                            )
                            .frame(height: 2)
                    }
                    .frame(height: 2)

                    // Playback mode controls
                    HStack {
                        Spacer()

                        // Repeat mode button
                        Button {
                            switch repeatMode {
                            case "none": repeatMode = "one"
                            case "one": repeatMode = "all"
                            case "all": repeatMode = "none"
                            default: repeatMode = "none"
                            }
                        } label: {
                            Image(systemName: repeatModeIcon)
                                .foregroundColor(
                                    repeatMode == "none" ? .secondary : .accentColor)
                        }

                        // Autoplay button
                        Button {
                            autoplay.toggle()
                        } label: {
                            Image(systemName: "forward.end")
                                .foregroundColor(autoplay ? .accentColor : .secondary)
                        }

                        Spacer()
                    }
                    .font(.caption)

                    // Main controls
                    HStack(spacing: 24) {
                        Spacer()

                        Button(action: { ttsQueue.previous() }) {
                            Image(systemName: "backward.fill")
                                .font(.title2)
                                .foregroundColor((!ttsQueue.playlist.isEmpty &&
                                                 (ttsQueue.currentIndex > 0 || repeatMode == "all"))
                                                ? .primary : .secondary)
                        }
                        .disabled(ttsQueue.playlist.isEmpty ||
                                  (ttsQueue.currentIndex == 0 && repeatMode != "all"))

                        Button(action: {
                            if ttsQueue.isPlaying {
                                ttsQueue.pause()
                            } else {
                                ttsQueue.resume()
                            }
                        }) {
                            Image(
                                systemName: ttsQueue.isPlaying
                                    ? "pause.circle.fill" : "play.circle.fill"
                            )
                            .font(.system(size: 44))
                            .foregroundColor(.accentColor)
                        }
                        .disabled(ttsQueue.playlist.isEmpty)

                        Button(action: { ttsQueue.next() }) {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                                .foregroundColor(
                                    (!ttsQueue.playlist.isEmpty &&
                                     (ttsQueue.currentIndex < ttsQueue.playlist.count - 1 || repeatMode == "all"))
                                        ? .primary : .secondary)
                        }
                        .disabled(ttsQueue.playlist.isEmpty ||
                                  (ttsQueue.currentIndex >= ttsQueue.playlist.count - 1 && repeatMode != "all"))

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .background(
                    colorScheme == .dark ? Color.black : Color.white
                )
            }
            .navigationTitle("Text to Speech")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close Player", systemImage: "xmark.square")
                            .labelStyle(.titleAndIcon)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        ttsQueue.clear()
                        dismiss()
                    } label: {
                        Label("Clear Playlist", systemImage: "eraser")
                            .labelStyle(.titleAndIcon)
                    }                    
                    .disabled(ttsQueue.playlist.isEmpty)
                }
            }
        }
        .frame(
            minWidth: 300, idealWidth: 400, maxWidth: .infinity,
            minHeight: 400, idealHeight: 600, maxHeight: .infinity
        )
        .presentationDetents([.medium, .large])
    }

    private var repeatModeIcon: String {
        switch repeatMode {
        case "none": return "repeat"
        case "one": return "repeat.1"
        case "all": return "repeat.circle"
        default: return "repeat"
        }
    }
}
