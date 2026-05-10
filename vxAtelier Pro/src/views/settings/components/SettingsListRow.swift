import SwiftUI

struct SettingsListRow<Content: View>: View {
    let selectionEnabled: Bool
    let selected: Bool
    let title: String
    let subtitle: String?
    let icons: [Image]
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let content: Content?
    
    @AppStorage(AppSettings.Keys.showRowToolButtons) private var showRowToolButtons: Bool = AppDefaults.showRowToolButtons
    
    init(
        title: String,
        subtitle: String? = nil,
        icons: [Image] = [],
        selectionEnabled: Bool = false,
        selected: Bool = false,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content? = { nil }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icons = icons
        self.selectionEnabled = selectionEnabled
        self.selected = selected
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            if selectionEnabled {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? .accentColor : .secondary)
            }
            VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                Text(title)
                    .font(.headline)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let content = content {
                    content
                }
            }
            .layoutPriority(1)
            
            Spacer()
            
            ForEach(icons.indices, id: \.self) { idx in
                icons[idx]
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if showRowToolButtons {
                if let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.borderless)
                }
                if let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .rowActions(onEdit: onEdit, onDelete: onDelete)
        .padding(AppDefaults.paddingSmall)
        .background(Color.secondary.opacity(AppDefaults.sectionBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
    }
}
