import SwiftUI
import UniformTypeIdentifiers

struct PromptExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var templates: [PromptTemplateExportData]

    init(templates: [PromptTemplateExportData]) {
        self.templates = templates
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        self.templates = try decoder.decode([PromptTemplateExportData].self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(templates)
        return FileWrapper(regularFileWithContents: data)
    }
}
