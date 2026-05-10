import SwiftUI

/// Reusable action bar with primary action, menu for secondary actions, and optional add button
struct SettingsActionBar<PrimaryLabel: View, AddLabel: View>: View {
    // Primary action
    let primaryAction: () -> Void
    let primaryLabel: PrimaryLabel
    
    // Secondary actions
    let secondaryActions: [MenuAction]
    
    let addAction: (() -> Void)?
    let addLabel: AddLabel?
    
    init(
        @ViewBuilder primaryLabel: () -> PrimaryLabel,
        primaryAction: @escaping () -> Void,
        secondaryActions: [MenuAction] = [],
        addAction: @escaping () -> Void,
        @ViewBuilder addLabel: () -> AddLabel
    ) {
        self.primaryLabel = primaryLabel()
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
        self.addAction = addAction
        self.addLabel = addLabel()
    }

    init(
        @ViewBuilder primaryLabel: () -> PrimaryLabel,
        primaryAction: @escaping () -> Void,
        secondaryActions: [MenuAction] = []
    ) where AddLabel == EmptyView {
        self.primaryLabel = primaryLabel()
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
        self.addAction = nil
        self.addLabel = nil
    }
    
    var body: some View {
        HStack(spacing: AppDefaults.paddingMedium) {
            // Primary action
            Button(action: primaryAction) {
                primaryLabel
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            // Secondary actions in menu
            if !secondaryActions.isEmpty {
                Menu {
                    ForEach(secondaryActions) { action in
                        if action.isSeparator {
                            Divider()
                        } else {
                            Button(role: action.isDestructive ? .destructive : nil) {
                                action.handler()
                            } label: {
                                Label(action.title, systemImage: action.iconName)
                            }
                        }
                    }
                } label: {
                    Label("More Actions", systemImage: "ellipsis.circle")
                }
                #if os(macOS)
                .menuStyle(.borderedButton)
                #endif
            }
            
            // Add button (optional)
            if let addAction = addAction, let addLabel = addLabel {
                Button(action: addAction) {
                    addLabel
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // Represents a menu action item
    struct MenuAction: Identifiable {
        let id = UUID()
        let title: String
        let iconName: String
        let handler: () -> Void
        let isDestructive: Bool
        let isSeparator: Bool
        
        init(
            title: String = "",
            iconName: String = "",
            isDestructive: Bool = false,
            isSeparator: Bool = false,
            handler: @escaping () -> Void = {}
        ) {
            self.title = title
            self.iconName = iconName
            self.isDestructive = isDestructive
            self.isSeparator = isSeparator
            self.handler = handler
        }
        
        static func separator() -> MenuAction {
            MenuAction(isSeparator: true)
        }
    }

}
