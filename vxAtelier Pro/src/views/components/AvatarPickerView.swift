import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#elseif os(iOS)
import UIKit
#endif

/// A reusable avatar picker view for macOS and iOS.
/// Shows the current avatar, allows picking a new image, and removing the avatar.
struct AvatarPickerView: View {
    let title: String
    @Binding var imageData: Data?
    let size: CGFloat
    let strokeWidth: CGFloat?

    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack {
                Spacer()
                AvatarView(imageData: imageData, size: size, strokeWidth: strokeWidth)
                Spacer()
            }
            HStack {
                Spacer()
                Button(action: {
                    vxAtelierPro.log.debug("Avatar picker button tapped")
                    #if os(macOS)
                    presentOpenPanel()
                    #else
                    isImporting = true
                    #endif
                }) {
                    Text(imageData == nil ? "Add Avatar" : "Change Avatar")
                }
                .buttonStyle(.bordered)

                if imageData != nil {
                    Button(role: .destructive) {
                        vxAtelierPro.log.info("Avatar image removed via picker")
                        imageData = nil
                    } label: {
                        Text("Remove Avatar")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
        #if os(iOS)
        .sheet(isPresented: $isImporting) {
            ImagePicker(selectedImage: { image in
                if let data = image.jpegData(compressionQuality: 0.8) {
                    vxAtelierPro.log.info("Updated avatar image from image picker")
                    imageData = data
                } else {
                    vxAtelierPro.log.error("Failed to get JPEG data for image from picker")
                }
            })
        }
        #endif
    }

#if os(macOS)
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType.heic,
            UTType.tiff,
            UTType.gif,
            UTType.bmp
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose an Avatar Image"
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                vxAtelierPro.log.debug("NSOpenPanel returned URL: \(url)")
                do {
                    let data = try FileHelper.loadImageData(from: url)
                    if let nsImage = NSImage(data: data) {
                        vxAtelierPro.log.info("Successfully created NSImage from data")
                        DispatchQueue.main.async {
                            imageData = nsImage.tiffRepresentation
                        }
                    } else {
                        vxAtelierPro.log.error("Failed to create NSImage from data")
                    }
                } catch let fileError as FileHelper.FileError {
                    vxAtelierPro.log.error("FileHelper error loading image: \(fileError)")
                } catch {
                    vxAtelierPro.log.error("Unexpected error loading image: \(error.localizedDescription)")
                }
            } else {
                vxAtelierPro.log.debug("NSOpenPanel was cancelled or no file selected")
            }
        }
    }
#endif
} 