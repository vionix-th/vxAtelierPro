import SwiftUI

#if canImport(MarkdownUI)
import MarkdownUI
#endif

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renderer that uses MarkdownUI for all markdown rendering.
struct MarkdownUIRenderer: View {
    let markdown: String
    
    @AppStorage(AppSettings.Keys.isMarkdownTextSelectable) private var isMarkdownTextSelectable: Bool = AppDefaults.isMarkdownTextSelectable
    
    var body: some View {
        Group {
            #if canImport(MarkdownUI)
            Markdown(markdown)
                .markdownBlockStyle(\.codeBlock) { configuration in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if let lang = configuration.language?.split(separator: " ").first.map(String.init), !lang.isEmpty {
                                Text(lang.uppercased())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Spacer()
                            Button {
                                copyToClipboard(configuration.content)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .labelStyle(.iconOnly)
                                    .font(.caption)
                            }
                            #if os(macOS)
                            .buttonStyle(PlainButtonStyle())
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                        ScrollView(.horizontal, showsIndicators: true) {
                            configuration.label
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

            #else
            // Minimal fallback when MarkdownUI is not available in the build
            Text(markdown)
            #endif
        }
        .padding(AppDefaults.paddingMedium)
        .modifier(MarkdownSelectableModifier(enabled: isMarkdownTextSelectable))
    }
}

// Local modifier to avoid dependency on legacy modules
private struct MarkdownSelectableModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

// Clipboard helper
private func copyToClipboard(_ text: String) {
    #if os(macOS)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}

