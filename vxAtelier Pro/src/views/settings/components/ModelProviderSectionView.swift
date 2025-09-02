import SwiftUI

// MARK: - Models Section View
struct ModelProviderSectionView: View {
    let title: String
    let models: [ModelItem]
    let onEditModel: (ModelItem) -> Void
    let onDeleteModel: (ModelItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppDefaults.sectionHeaderColor)
            
            List {
                ForEach(models.sorted(by: { $0.name < $1.name })) { model in
                    SettingsListRow(
                        title: model.name,
                        subtitle: model.provider,
                        icons: model.capabilities.map { Image(systemName: $0.systemName) },
                        onEdit: { onEditModel(model) },
                        onDelete: { onDeleteModel(model) }
                    ) {
                        Text("Context size: \(model.contextSize)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .settingsRowActions(
                        onEdit: { onEditModel(model) },
                        onDelete: { onDeleteModel(model) }
                    )
                }
            }
        }
    }
}

// MARK: - Model Context Size Row
struct ModelContextSizeRow: View {
    let model: ModelItem
    let onEdit: (ModelItem) -> Void
    
    var body: some View {
        Button {
            vxAtelierPro.log.debug("⏱️ ModelContextSizeRow: Button tapped")
            onEdit(model)
            vxAtelierPro.log.debug("⏱️ ModelContextSizeRow: Sheet presentation triggered")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: AppDefaults.paddingSmall) {
                    Text(model.name)
                        .font(.system(.body, design: .monospaced))
                    HStack(spacing: AppDefaults.paddingMedium) {
                        Text(model.provider)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(model.capabilities, id: \.self) { capability in
                            Image(systemName: capability.systemName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .layoutPriority(1)
                
                Spacer()
                
                Text("\(model.contextSize)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, AppDefaults.paddingSmall)
    }
} 