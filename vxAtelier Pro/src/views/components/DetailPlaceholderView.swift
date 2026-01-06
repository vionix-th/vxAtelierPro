import SwiftUI

struct DetailPlaceholderView: View {
    let hasAPIConfiguration: Bool
    let onNewDialog: () -> Void
    let onNewProject: () -> Void
    let onConfigureAPI: () -> Void

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
            Text(
                hasAPIConfiguration
                    ? "Start by creating a new dialog or project. Organize your conversations and ideas with ease."
                    : "Configure an API provider to create dialogs and projects."
            )
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppDefaults.paddingLarge)
                .padding(.bottom, AppDefaults.paddingLarge)
            VStack(spacing: AppDefaults.paddingLarge) {
                if hasAPIConfiguration {
                    Button(action: {
                        onNewDialog()
                    }) {
                        Label("New Dialog", systemImage: "plus.bubble")
                            .font(.title3.bold())
                            .padding(.vertical, AppDefaults.paddingSmall)
                            .padding(.horizontal, AppDefaults.paddingLarge)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .accessibilityIdentifier("welcome-new-dialog")

                    Button(action: {
                        onNewProject()
                    }) {
                        Label("New Project", systemImage: "folder.badge.plus")
                            .font(.title3.bold())
                            .padding(.vertical, AppDefaults.paddingSmall)
                            .padding(.horizontal, AppDefaults.paddingLarge)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityIdentifier("welcome-new-project")
                } else {
                    Button(action: {
                        onConfigureAPI()
                    }) {
                        Label("Configure API", systemImage: "key.fill")
                            .font(.title3.bold())
                            .padding(.vertical, AppDefaults.paddingSmall)
                            .padding(.horizontal, AppDefaults.paddingLarge)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .accessibilityIdentifier("welcome-configure-api")
                }
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
