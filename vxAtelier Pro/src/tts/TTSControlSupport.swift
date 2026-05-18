import SwiftData
import SwiftUI

enum TTSTab: Hashable {
    case player
    case playlists
}

struct PlaylistEditor: Identifiable {
    let id = UUID()
    let title: String
    let name: String
    let playlistID: PersistentIdentifier?
}

struct PlaylistEntryEditor: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let role: TTSPlaylistRole
    let playlistID: PersistentIdentifier?
    let entryID: PersistentIdentifier?
}

struct PlaylistEditorSheet: View {
    let title: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String

    init(title: String, name: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onCancel = onCancel
        self.onSave = onSave
        _draftName = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
            Text(title)
                .font(.title3.weight(.semibold))

            TextField("Playlist name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack(spacing: AppDefaults.paddingSmall) {
                Spacer(minLength: 0)

                Button("Cancel") {
                    onCancel()
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(AppDefaults.paddingLarge)
        .frame(minWidth: 360, minHeight: 180)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        onSave(draftName)
        dismiss()
    }
}

struct PlaylistEntryEditorSheet: View {
    let title: String
    let text: String
    let role: TTSPlaylistRole
    let onCancel: () -> Void
    let onSave: (String, TTSPlaylistRole) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftText: String
    @State private var draftRole: TTSPlaylistRole

    init(title: String, text: String, role: TTSPlaylistRole, onCancel: @escaping () -> Void, onSave: @escaping (String, TTSPlaylistRole) -> Void) {
        self.title = title
        self.text = text
        self.role = role
        self.onCancel = onCancel
        self.onSave = onSave
        _draftText = State(initialValue: text)
        _draftRole = State(initialValue: role)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
            Text(title)
                .font(.title3.weight(.semibold))

            TextEditorWithPlaceholder(
                text: $draftText,
                placeholder: "Enter the entry text"
            )
            .frame(minHeight: 180)

            Picker("", selection: $draftRole) {
                ForEach(TTSPlaylistRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: AppDefaults.paddingSmall) {
                Spacer(minLength: 0)

                Button("Cancel") {
                    onCancel()
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(AppDefaults.paddingLarge)
        .frame(minWidth: 460, minHeight: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous))
    }

    private var canSave: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        onSave(draftText, draftRole)
        dismiss()
    }
}

struct TextEditorWithPlaceholder: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(4)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .allowsHitTesting(false)
            }
        }
    }
}
