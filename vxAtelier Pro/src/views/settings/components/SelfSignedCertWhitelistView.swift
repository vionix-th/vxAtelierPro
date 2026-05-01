import SwiftUI
import Foundation

/// A reusable view for managing a whitelist of regex patterns for self-signed certificates.
public struct SelfSignedCertWhitelistView: View {
    @Binding var whitelist: [String]
    @Environment(\.isEnabled) private var isEnabled
    private let listAnimation: Animation = .easeInOut(duration: 0.18)
    
    @State private var editingRegexIndex: Int? = nil
    @State private var editingRegexText: String = ""
    @State private var showRegexEditSheet: Bool = false
    @State private var regexValidationError: String? = nil
    
    public init(whitelist: Binding<[String]>) {
        self._whitelist = whitelist
    }
    
    // Platform adaptive background color
    private var mainBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
    private var secondaryBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor).opacity(0.7)
        #else
        return Color(UIColor.secondarySystemBackground).opacity(0.7)
        #endif
    }
    
    private func deleteRegex(at offset: Int) {
        withAnimation(listAnimation) {
            var arr = whitelist
            arr.remove(at: offset)
            whitelist = arr
        }
    }
    
    public var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView(isEnabled: isEnabled, onAdd: {
                    editingRegexIndex = nil
                    editingRegexText = ""
                    regexValidationError = nil
                    showRegexEditSheet = true
                })
                HelpTextView()
                RegexListView(
                    regexes: whitelist,
                    isEnabled: isEnabled,
                    onEdit: { idx, regex in
                        editingRegexIndex = idx
                        editingRegexText = regex
                        regexValidationError = nil
                        showRegexEditSheet = true
                    },
                    onDelete: { offset in
                        deleteRegex(at: offset)
                    },
                    secondaryBackground: secondaryBackground
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(mainBackground)
                    .opacity(0.95)
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, lineWidth: 1)
                    .opacity(0.18)
            )
            if !isEnabled {
                DisabledOverlayView(mainBackground: mainBackground)
            }
        }
        .sheet(isPresented: $showRegexEditSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 24) {
                    Text(editingRegexIndex == nil ? "Add Regex Pattern" : "Edit Regex Pattern")
                        .font(.title2)
                        .bold()
                    TextField("Regular Expression", text: $editingRegexText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                    if let error = regexValidationError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    Spacer()
                    HStack {
                        Button("Cancel") {
                            showRegexEditSheet = false
                        }
                        Spacer()
                        Button(editingRegexIndex == nil ? "Add" : "Save") {
                            if SelfSignedCertWhitelistView.isValidRegex(editingRegexText) {
                                if let idx = editingRegexIndex {
                                    whitelist[idx] = editingRegexText
                                } else {
                                    withAnimation(listAnimation) { whitelist.append(editingRegexText) }
                                }
                                showRegexEditSheet = false
                            } else {
                                regexValidationError = "Invalid regular expression."
                            }
                        }
                        .disabled(editingRegexText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .frame(minWidth: 350, minHeight: 200)
            }
        }
    }
}

private struct HeaderView: View {
    let isEnabled: Bool
    let onAdd: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .foregroundColor(.accentColor)
                .imageScale(.large)
                .accessibilityHidden(true)
            Text("Self-Signed Certificate Whitelist")
                .font(.headline)
                .bold()
            Spacer()
            Button(action: onAdd) {
                Label("Add Regex", systemImage: "plus.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundColor(isEnabled ? .accentColor : .gray)
                    .opacity(isEnabled ? 1.0 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel("Add regex pattern")
            .help(isEnabled ? "Add a new regex pattern" : "Enable self-signed certificates to add patterns")
        }
        .padding(.bottom, 2)
    }
}

private struct HelpTextView: View {
    var body: some View {
        Text("Add regular expressions to allow specific URLs for self-signed certificates.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom, 8)
    }
}

private struct RegexListView: View {
    let regexes: [String]
    let isEnabled: Bool
    let onEdit: (Int, String) -> Void
    let onDelete: (Int) -> Void
    let secondaryBackground: Color
    var body: some View {
        VStack(spacing: 0) {
            if regexes.isEmpty {
                Text("No whitelisted patterns. Add a regex to allow URLs for self-signed certificates.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(Array(regexes.enumerated()), id: \.offset) { item in
                    let offset = item.offset
                    let regex = item.element
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(regex)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(isEnabled ? .primary : .gray)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityLabel("Regex pattern: \(regex)")
                        Spacer()
                        Button {
                            onEdit(offset, regex)
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(isEnabled ? .accentColor : .gray)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!isEnabled)
                        .accessibilityLabel("Edit regex pattern")
                        Button(role: .destructive) {
                            onDelete(offset)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(isEnabled ? .red : .gray)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!isEnabled)
                        .accessibilityLabel("Delete regex pattern")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                    .padding(.vertical, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(secondaryBackground)
                        .opacity(0.7)
                )
        )
    }
}

private struct DisabledOverlayView: View {
    let mainBackground: Color
    var body: some View {
        Color.white.opacity(0.6)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                VStack {
                    Image(systemName: "lock.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                        .padding(.bottom, 2)
                    Text("Enable above to edit whitelist")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(8)
                .background(mainBackground)
                .opacity(0.7)
                .cornerRadius(10)
                .shadow(radius: 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Whitelist editing is disabled. Enable self-signed certificates to edit.")
            )
    }
}

// ... static helpers remain unchanged ...
public extension SelfSignedCertWhitelistView {
    static func isValidRegex(_ pattern: String) -> Bool {
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return true
        } catch {
            return false
        }
    }
    static func isURLAllowedByWhitelist(_ url: URL, whitelist: [String]) -> Bool {
        let urlString = url.absoluteString
        for pattern in whitelist {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: urlString.utf16.count)
                if regex.firstMatch(in: urlString, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }
} 
