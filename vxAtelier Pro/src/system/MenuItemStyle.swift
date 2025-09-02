import SwiftUI

struct MenuItemStyle {
    static func label(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }
} 