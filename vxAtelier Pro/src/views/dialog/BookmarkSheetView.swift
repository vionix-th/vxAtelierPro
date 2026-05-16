import SwiftUI

struct BookmarkSheetView: View {
    @Binding var label: String
    let onBookmark: () -> Void
    let onCancel: () -> Void

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
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                Button("Bookmark") {
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
