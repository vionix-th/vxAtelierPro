import Foundation
import SwiftUI

/// Editor for regular-expression whitelist entries used with self-signed certificates.
public struct SelfSignedCertWhitelistView: View {
    @Binding var whitelist: [String]
    @Environment(\.isEnabled) private var isEnabled
    @State private var editingPattern: RegexPatternItem?
    @State private var editingText = ""
    @State private var validationError: String?
    @State private var confirmation: SettingsConfirmation?

    public init(whitelist: Binding<[String]>) {
        self._whitelist = whitelist
    }

    public var body: some View {
        Text("Add regular expressions to allow specific URLs for self-signed certificates.")
            .font(.caption)
            .foregroundStyle(.secondary)

        SettingsEntityRows(
            items: patternItems,
            emptyTitle: "No Whitelisted Patterns",
            emptySystemImage: "checkmark.shield",
            emptyDescription: "Add a regex to allow URLs for self-signed certificates.",
            selectionAction: { item in
                guard isEnabled else { return }
                editPattern(item)
            }
        ) { item in
            SettingsEntityRow(
                title: item.pattern,
                subtitle: nil,
                metadata: nil,
                systemImages: ["chevron.right"]
            )
            .fontDesign(.monospaced)
            .foregroundStyle(isEnabled ? .primary : .secondary)
        } actions: { item in
            guard isEnabled else { return [] }
            return [
                SettingsEntityAction(title: "Edit", systemImage: "pencil") {
                    editPattern(item)
                },
                SettingsEntityAction(title: "Delete", systemImage: "trash", role: .destructive) {
                    confirmation = SettingsConfirmation(
                        title: "Delete Whitelist Pattern",
                        message: "Delete this self-signed certificate whitelist pattern?",
                        confirmTitle: "Delete",
                        action: { _ in deletePattern(at: item.index) }
                    )
                }
            ]
        }

        Button {
            addPattern()
        } label: {
            Label("Add Regex Pattern", systemImage: "plus")
        }
        .disabled(!isEnabled)
        .sheet(item: $editingPattern) { item in
            NavigationStack {
                SettingsPage(title: item.isNew ? "Add Regex Pattern" : "Edit Regex Pattern") {
                    SettingsFormSection("Pattern") {
                        TextField("Regular Expression", text: $editingText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            #endif

                        if let validationError {
                            Text(validationError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editingPattern = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(item.isNew ? "Add" : "Save") {
                            saveEditingPattern(item)
                        }
                        .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .settingsConfirmationDialog($confirmation)
    }

    private var patternItems: [RegexPatternItem] {
        whitelist.enumerated().map { offset, pattern in
            RegexPatternItem(index: offset, pattern: pattern)
        }
    }

    private func addPattern() {
        editingText = ""
        validationError = nil
        editingPattern = RegexPatternItem(index: whitelist.count, pattern: "", isNew: true)
    }

    private func editPattern(_ item: RegexPatternItem) {
        editingText = item.pattern
        validationError = nil
        editingPattern = item
    }

    private func saveEditingPattern(_ item: RegexPatternItem) {
        let trimmedPattern = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SelfSignedCertWhitelistView.isValidRegex(trimmedPattern) else {
            validationError = "Invalid regular expression."
            return
        }

        if item.isNew {
            whitelist.append(trimmedPattern)
        } else if whitelist.indices.contains(item.index) {
            whitelist[item.index] = trimmedPattern
        }
        editingPattern = nil
    }

    private func deletePattern(at index: Int) {
        guard whitelist.indices.contains(index) else { return }
        whitelist.remove(at: index)
    }
}

/// Stored regular-expression entry in the self-signed certificate whitelist.
private struct RegexPatternItem: Identifiable {
    let index: Int
    let pattern: String
    var isNew = false

    var id: Int { index }
}

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
