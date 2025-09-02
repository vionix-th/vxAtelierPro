import SwiftUI

// MARK: - Permission Row View
/// Displays information about a specific permission type, its status, and an action button.
struct PermissionRowView: View {
    let type: PermissionType
    let status: PermissionStatus
    let action: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: AppDefaults.paddingMedium) {
            Image(systemName: type.systemImageName)
                .font(.title2)
                .frame(width: 30, alignment: .center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue)
                    .font(.headline)
                Text(type.usageDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status Indicator
            Text(status.description)
                .font(.subheadline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.2))
                .foregroundColor(status.color)
                .clipShape(Capsule())
            
            // Action Button
            Button {
                action()
            } label: {
                // Adjust label based on status
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
} 