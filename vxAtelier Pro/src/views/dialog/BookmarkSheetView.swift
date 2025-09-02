import SwiftUI
import SwiftData

struct BookmarkSheetView: View {
    @Binding var label: String
    let turn: ConversationTurn
    let event: TurnEvent?
    let onBookmark: () -> Void

    @Environment(QueryManager.self) private var queryManager

    private var backgroundColor: Color {
        #if os(macOS)
        return Color(.windowBackgroundColor)
        #else
        return Color(.systemBackground)
        #endif
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge)
                .fill(backgroundColor)
                .shadow(radius: 8)
            VStack(spacing: AppDefaults.paddingLarge) {
                Text("Add Bookmark")
                    .font(.title2.bold())
                    .padding(.top, AppDefaults.paddingMedium)
                TextField("Label", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: AppDefaults.fontSizeLarge))
                    .padding(.horizontal)
                    .submitLabel(.done)
                HStack {
                    Button("Cancel") {
                        onBookmark() // parent will dismiss
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Bookmark") {
                        if let event = event {
                            queryManager.insertBookmark(label: label, turn: turn, event: event)
                        } else {
                            queryManager.insertBookmark(label: label, turn: turn)
                        }
                        onBookmark()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, AppDefaults.paddingMedium)
            }
            .padding(.vertical, AppDefaults.paddingLarge)
            .frame(idealWidth: 340, idealHeight: 220)
        }
        .padding()
    }
} 