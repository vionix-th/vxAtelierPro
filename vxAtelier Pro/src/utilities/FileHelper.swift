import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
class FileHelper: NSObject {
    // Singleton instance for easy access
    static let shared = FileHelper()
    
    // MARK: - macOS Implementation
#if os(macOS)
    /// Saves data to a file on macOS using NSSavePanel
    /// - Parameters:
    ///   - data: The data to save (e.g., JSON data)
    ///   - filename: Suggested filename for the save dialog
    func save(data: Data, filename: String) async throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.json] // Restrict to JSON files
        
        // Show the save panel and wait for user response
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            vxAtelierPro.log.warning("User cancelled save panel for file '", file: #file, function: #function, line: #line)
            throw FileError.cancelled
        }
        
        // Write the data to the selected file
        do {
            try data.write(to: url)
            vxAtelierPro.log.info("Successfully saved file to \(url.path)", file: #file, function: #function, line: #line)
        } catch {
            vxAtelierPro.log.error("Failed to save file to \(url.path): \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
    }
    
    /// Loads data from a file on macOS using NSOpenPanel
    /// - Returns: The data from the selected file
    func load() async throws -> Data {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json] // Restrict to JSON files
        panel.allowsMultipleSelection = false
        
        // Show the open panel and wait for user response
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            vxAtelierPro.log.warning("User cancelled open panel for loading file", file: #file, function: #function, line: #line)
            throw FileError.cancelled
        }
        
        // Read and return the data from the selected file
        do {
            let data = try Data(contentsOf: url)
            vxAtelierPro.log.info("Successfully loaded file from \(url.path)", file: #file, function: #function, line: #line)
            return data
        } catch {
            vxAtelierPro.log.error("Failed to load file from \(url.path): \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
    }
    
    // MARK: - iOS Implementation
#elseif os(iOS)
    // Continuations to handle async document picker results
    private var saveContinuation: CheckedContinuation<Void, Error>?
    private var loadContinuation: CheckedContinuation<URL, Error>?
    
    /// Saves data to a file on iOS using UIDocumentPickerViewController
    /// - Parameters:
    ///   - data: The data to save (e.g., JSON data)
    ///   - filename: Suggested filename for the save operation
    func save(data: Data, filename: String) async throws {
        // Create a temporary file to hold the data
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
        } catch {
            vxAtelierPro.log.error("Failed to write temp file for saving: \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
        
        // Set up the document picker for exporting the file
        let picker = UIDocumentPickerViewController(forExporting: [tempURL])
        picker.delegate = self
        
        // Present the picker to the user
        guard let rootVC = rootViewController() else {
            vxAtelierPro.log.warning("No root view controller found for saving file", file: #file, function: #function, line: #line)
            throw FileError.noViewController
        }
        rootVC.present(picker, animated: true)
        
        // Wait for the user to pick a save location
        do {
            try await withCheckedThrowingContinuation { continuation in
                self.saveContinuation = continuation
            }
            vxAtelierPro.log.info("Successfully saved file via document picker", file: #file, function: #function, line: #line)
        } catch FileError.cancelled {
            vxAtelierPro.log.warning("User cancelled document picker for saving file", file: #file, function: #function, line: #line)
            throw FileError.cancelled
        } catch {
            vxAtelierPro.log.error("Failed to save file via document picker: \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
        
        // Clean up the temporary file
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    /// Loads data from a file on iOS using UIDocumentPickerViewController
    /// - Returns: The data from the selected file
    func load() async throws -> Data {
        // Set up the document picker for importing a file
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        
        // Present the picker to the user
        guard let rootVC = rootViewController() else {
            vxAtelierPro.log.warning("No root view controller found for loading file", file: #file, function: #function, line: #line)
            throw FileError.noViewController
        }
        rootVC.present(picker, animated: true)
        
        // Wait for the user to select a file
        let url: URL
        do {
            url = try await withCheckedThrowingContinuation { continuation in
                self.loadContinuation = continuation
            }
        } catch FileError.cancelled {
            vxAtelierPro.log.warning("User cancelled document picker for loading file", file: #file, function: #function, line: #line)
            throw FileError.cancelled
        } catch {
            vxAtelierPro.log.error("Failed to load file via document picker: \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
        
        // Access the security-scoped resource and read the data
        guard url.startAccessingSecurityScopedResource() else {
            vxAtelierPro.log.warning("Access denied to security-scoped resource: \(url.path)", file: #file, function: #function, line: #line)
            throw FileError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            vxAtelierPro.log.info("Successfully loaded file from \(url.path)", file: #file, function: #function, line: #line)
            return data
        } catch {
            vxAtelierPro.log.error("Failed to load file from \(url.path): \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
    }
    
    /// Finds the root view controller to present the document picker
    private func rootViewController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    if window.isKeyWindow {
                        return window.rootViewController
                    }
                }
            }
        }
        return nil
    }
#endif
    
    // MARK: - Error Types
    /// Errors that can occur during file operations
    enum FileError: Error {
        case cancelled              // User cancelled the operation
#if os(iOS)
        case noViewController       // No root view controller found
        case noFileSelected         // No file was selected
#endif
        // Universal Errors
        case accessDenied           // Couldn't access the file security scope or path
        case readFailed(Error)      // Failed to read data from the file
    }
    
    // MARK: - Document Directory Access
    
    /// Returns the URL to the documents directory
    func getDocumentsDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Models File Operations
    
    /// Opens a file picker to save models data
    @MainActor
    func saveModels(_ data: Data) async throws {
    #if os(macOS)
        do {
            try await save(data: data, filename: "vxatelier-models-\(Date().ISO8601Format()).json")
            vxAtelierPro.log.info("Successfully saved models file", file: #file, function: #function, line: #line)
        } catch {
            vxAtelierPro.log.error("Failed to save models file: \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
    #else
        // iOS implementation would go here
        // For now, just save to documents directory
        let url = getDocumentsDirectory().appendingPathComponent("vxatelier-models-\(Date().ISO8601Format()).json")
        do {
            try data.write(to: url)
            vxAtelierPro.log.info("Successfully saved models file to \(url.path)", file: #file, function: #function, line: #line)
        } catch {
            vxAtelierPro.log.error("Failed to save models file to \(url.path): \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
    #endif
    }
    
    /// Opens a file picker to load models data
    @MainActor
    func loadModels() async throws -> Data {
    #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Models"
        panel.message = "Choose a models file to import"
        
        // Show the open panel and wait for user response
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            vxAtelierPro.log.warning("User cancelled open panel for loading models file", file: #file, function: #function, line: #line)
            throw FileError.cancelled
        }
        
        // Read and return the data from the selected file
        do {
            let data = try Data(contentsOf: url)
            vxAtelierPro.log.info("Successfully loaded models file from \(url.path)", file: #file, function: #function, line: #line)
            return data
        } catch {
            vxAtelierPro.log.error("Failed to load models file from \(url.path): \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
    #else
        // iOS implementation would go here
        // For now, just load from documents directory
        let url = getDocumentsDirectory().appendingPathComponent("vxatelier-models.json")
        do {
            let data = try Data(contentsOf: url)
            vxAtelierPro.log.info("Successfully loaded models file from \(url.path)", file: #file, function: #function, line: #line)
            return data
        } catch {
            vxAtelierPro.log.error("Failed to load models file from \(url.path): \(error.localizedDescription)", file: #file, function: #function, line: #line)
            throw error
        }
    #endif
    }

    // MARK: - Image Loading

    /// Loads image data from a security-scoped URL.
    /// This function handles starting and stopping security-scoped access.
    /// - Parameter url: The security-scoped URL of the image file.
    /// - Returns: The image data.
    /// - Throws: `FileError` if access is denied or reading fails.
    static func loadImageData(from url: URL) throws -> Data {
        guard url.startAccessingSecurityScopedResource() else {
            vxAtelierPro.log.error("Failed to get security-scoped access to file: \(url.path)")
            throw FileError.accessDenied
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }

        do {
            let imageData = try Data(contentsOf: url)
            vxAtelierPro.log.debug("Successfully read \(imageData.count) bytes from \(url.path)")
            return imageData
        } catch {
            vxAtelierPro.log.error("Failed to read image data from \(url.path): \(error.localizedDescription)")
            throw FileError.readFailed(error)
        }
    }
}
// MARK: - iOS Delegate Methods
#if os(iOS)
extension FileHelper: UIDocumentPickerDelegate {
    /// Called when the user picks a document(s)
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let saveCont = saveContinuation {
            // Resume save operation
            saveCont.resume(returning: ())
            saveContinuation = nil
        } else if let loadCont = loadContinuation {
            // Resume load operation with the selected URL
            if let url = urls.first {
                loadCont.resume(returning: url)
            } else {
                loadCont.resume(throwing: FileError.noFileSelected)
            }
            loadContinuation = nil
        }
    }
    
    /// Called when the user cancels the document picker
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if let saveCont = saveContinuation {
            saveCont.resume(throwing: FileError.cancelled)
            saveContinuation = nil
        } else if let loadCont = loadContinuation {
            loadCont.resume(throwing: FileError.cancelled)
            loadContinuation = nil
        }
    }
}
#endif
