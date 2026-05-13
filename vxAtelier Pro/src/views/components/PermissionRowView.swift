import SwiftUI

// MARK: - Permission Row View
/// Displays information about a specific permission type, its status, and an action button.
struct PermissionRowView: View {
    let type: PermissionType
    let status: PermissionStatus
    let action: () -> Void
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppDefaults.paddingMedium) {
                label
                Spacer(minLength: AppDefaults.paddingLarge)
                statusBadge
                actionButton
            }

            VStack(alignment: .leading, spacing: AppDefaults.paddingMedium) {
                label
                HStack {
                    statusBadge
                    Spacer()
                    actionButton
                }
            }
        }
        .padding(.vertical, AppDefaults.paddingSmall)
    }

    private var label: some View {
        HStack(alignment: .top, spacing: AppDefaults.paddingMedium) {
            Image(systemName: type.systemImageName)
                .font(.title3)
                .frame(minWidth: 28, alignment: .center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(type.rawValue)
                    .font(.headline)
                Text(type.usageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusBadge: some View {
        Text(status.description)
            .font(.caption.weight(.medium))
            .padding(.horizontal, AppDefaults.paddingMedium)
            .padding(.vertical, AppDefaults.paddingSmall)
            .background(status.color.opacity(0.18), in: Capsule())
            .foregroundStyle(status.color)
    }

    private var actionButton: some View {
        Button {
            action()
        } label: {
            switch status {
            case .notDetermined:
                Text("Request Access")
            case .denied, .restricted, .authorized, .limited:
                Text("Open Settings")
            }
        }
        .buttonStyle(.bordered)
    }
}
