import SwiftUI

struct FilterButton: View {
    let logType: LoggingService.LogType?
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let type = logType {
                    Image(systemName: type.systemImage)
                        .foregroundColor(type.color)
                        .font(.caption2)
                        .frame(width: 14, height: 14)
                }

                Text(label)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .primary : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
