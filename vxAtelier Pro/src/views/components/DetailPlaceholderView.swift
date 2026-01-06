import SwiftUI

struct DetailPlaceholderView: View {
    let canCreate: Bool
    let onNewDialog: () -> Void
    let onNewProject: () -> Void

    var body: some View {
        VStack(spacing: AppDefaults.paddingLarge) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundColor(.accentColor)
                .shadow(radius: 8)
                .padding(.bottom, AppDefaults.paddingMedium)
            Text("Welcome to vxAtelier Pro")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, AppDefaults.paddingSmall)
            Text("Start by creating a new dialog or project. Organize your conversations and ideas with ease.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppDefaults.paddingLarge)
                .padding(.bottom, AppDefaults.paddingLarge)
            VStack(spacing: AppDefaults.paddingLarge) {
                Button(action: {
                    if canCreate { onNewDialog() }
                }) {
                    Label("New Dialog", systemImage: "plus.bubble")
                        .font(.title3.bold())
                        .padding(.vertical, AppDefaults.paddingSmall)
                        .padding(.horizontal, AppDefaults.paddingLarge)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .accessibilityIdentifier("welcome-new-dialog")
                .disabled(!canCreate)
                .help(canCreate ? "" : "API configuration required to create a new dialog")

                Button(action: {
                    if canCreate { onNewProject() }
                }) {
                    Label("New Project", systemImage: "folder.badge.plus")
                        .font(.title3.bold())
                        .padding(.vertical, AppDefaults.paddingSmall)
                        .padding(.horizontal, AppDefaults.paddingLarge)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityIdentifier("welcome-new-project")
                .disabled(!canCreate)
                .help(canCreate ? "" : "API configuration required to create a new project")
            }
            .padding(.bottom, AppDefaults.paddingLarge)
            Spacer()
        }
        .padding(AppDefaults.paddingLarge)
        .background(
            RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusLarge, style: .continuous)
                .fill(
                    {
                        #if os(iOS)
                            Color(uiColor: .secondarySystemBackground)
                        #elseif os(macOS)
                            Color(nsColor: .windowBackgroundColor)
                        #else
                            Color(.systemBackground)
                        #endif
                    }()
                )
                .shadow(color: .black.opacity(0.04), radius: 16, x: 0, y: 4)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
