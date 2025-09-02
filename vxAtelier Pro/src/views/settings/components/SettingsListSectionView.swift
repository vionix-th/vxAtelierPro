import SwiftUI

// MARK: - New Reusable List Section Component

/// A reusable view for displaying a list of items within a standard settings section container.
struct SettingsListSectionView<Item, RowContent: View>: View where Item: Identifiable {
    let title: String
    let items: [Item]
    @ViewBuilder let rowContent: (Item) -> RowContent
    
    // Optional closure for deleting items using onDelete modifier (if items conform to required protocols)
    // let onDelete: ((IndexSet) -> Void)? = nil // Example: Add if needed

    var body: some View {
        // Use the existing SettingsSectionView as the base container
        SettingsSectionView(title: title) {
            // Internal VStack to hold the rows and dividers
            VStack(alignment: .leading, spacing: 0) { // Use 0 spacing, dividers handle it
                if items.isEmpty {
                    Text("No items to display.") // Generic empty state
                        .foregroundColor(.secondary)
                        .padding(.vertical, AppDefaults.paddingLarge)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        rowContent(item) // Use the provided closure to build the row

                        // Add divider except for the last item
                        if index < items.count - 1 {
                            Divider()
                               .padding(.horizontal, AppDefaults.paddingSmall) // Keep slight indent
                        }
                    }
                    // Apply onDelete modifier here if needed and `onDelete` is provided
                    // .onDelete(perform: onDelete)
                }
            }
        }
    }
} 