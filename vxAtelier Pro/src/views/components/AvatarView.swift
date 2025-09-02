import SwiftUI

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif

/// A view that displays an avatar image from optional Data,
/// handling platform differences and showing a placeholder if data is nil or invalid.
struct AvatarView: View {
    let imageData: Data?
    let size: CGFloat
    let strokeWidth: CGFloat? // Optional stroke width

    // Computed property for placeholder
    private var placeholder: some View {
        Image(systemName: "person.circle.fill") // Using fill for better visibility
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(.secondary) // Using secondary for placeholder look
    }

    // Computed property for the overlay (stroke)
    @ViewBuilder
    private var strokeOverlay: some View {
        if let strokeWidth = strokeWidth, strokeWidth > 0 {
            Circle().stroke(Color.accentColor, lineWidth: strokeWidth)
        } else {
            EmptyView()
        }
    }

    var body: some View {
        Group {
            if let data = imageData {
                #if os(macOS)
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        placeholder // Show placeholder if NSImage fails
                    }
                #elseif os(iOS)
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        placeholder // Show placeholder if UIImage fails
                    }
                #else
                    placeholder // Fallback for other platforms
                #endif
            } else {
                placeholder // Show placeholder if imageData is nil
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(strokeOverlay) // Apply the conditional stroke
    }
}

// MARK: - Previews
struct AvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AvatarView(imageData: nil, size: 60, strokeWidth: 2)
                .previewDisplayName("Placeholder with Stroke")

            // Example with placeholder data (replace with actual image data if available)
            AvatarView(imageData: Data(), size: 80, strokeWidth: nil) // Example invalid data
                .previewDisplayName("Invalid Data")

            AvatarView(imageData: nil, size: 40, strokeWidth: 0)
                 .previewDisplayName("Placeholder No Stroke")

             // Add a preview with actual image data if possible,
             // e.g., by loading from assets or creating dummy data.
        }
        .padding()
    }
} 