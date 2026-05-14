import SwiftUI

/// Card-style container for settings subpanels.
struct SettingsCardView<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppDefaults.paddingLarge) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppDefaults.sectionHeaderColor)
            
            VStack(spacing: AppDefaults.paddingMedium) {
                content
            }
            .padding(AppDefaults.paddingLarge)
            .background(Color.secondary.opacity(AppDefaults.sectionBackgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius: AppDefaults.cornerRadiusMedium))
        }
    }
} 
