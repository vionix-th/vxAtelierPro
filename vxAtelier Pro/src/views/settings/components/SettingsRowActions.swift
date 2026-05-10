import SwiftUI

struct SettingsRowActions: ViewModifier {
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let onEdit = onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
            .contextMenu {
                if let onEdit = onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }
}

extension View {
    func rowActions(onEdit: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) -> some View {
        self.modifier(SettingsRowActions(onEdit: onEdit, onDelete: onDelete))
    }
}
