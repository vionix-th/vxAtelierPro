#if os(macOS)
    import Foundation
    import AppKit

    /// Represents basic information about a shortcut
    public struct ShortcutInfo {
        public let id: String
        public let name: String
    }

    /// Manages interaction with Apple Shortcuts
    public class ShortcutsManager {
        /// Shared instance for the ShortcutsManager
        public static let shared = ShortcutsManager()
        
        private init() {}
        
        /// Gets all shortcuts from the system using the 'shortcuts' command-line tool
        /// - Returns: Array of ShortcutInfo objects
        public func getAllShortcuts() async -> [ShortcutInfo] {
            await vxAtelierPro.log.debug("Fetching all shortcuts using CLI")
            
            // Create a Process to run the 'shortcuts list' command with identifiers
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list", "--show-identifiers"]  // Using --show-identifiers flag
            process.standardOutput = pipe
            process.standardError = pipe
            
            var shortcuts: [ShortcutInfo] = []
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    // The output with --show-identifiers flag is in format:
                    // Shortcut Name (IDENTIFIER-UUID)
                    await vxAtelierPro.log.debug("Raw CLI output: \(output)")
                    
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if line.isEmpty { continue }
                        
                        // Parse the line in the format "Name (UUID)"
                        if let range = line.range(of: " ("), let endRange = line.range(of: ")") {
                            let name = String(line[..<range.lowerBound])
                            let idStart = line.index(range.upperBound, offsetBy: 0)
                            if idStart < endRange.lowerBound {
                                let id = String(line[idStart..<endRange.lowerBound])
                                shortcuts.append(ShortcutInfo(id: id, name: name))
                            }
                        } else {
                            // Fallback if the format is not as expected
                            let id = line.stableHash()
                            shortcuts.append(ShortcutInfo(id: id, name: line))
                        }
                    }
                    
                    await vxAtelierPro.log.debug("Found \(shortcuts.count) shortcuts via CLI")
                } else {
                    await vxAtelierPro.log.error("Could not decode command output")
                }
            } catch {
                await vxAtelierPro.log.error("Error running shortcuts command: \(error.localizedDescription)")
            }
            
            return shortcuts
        }
        
        /// Runs a specific shortcut by name or id using the 'shortcuts' command-line tool
        /// - Parameters:
        ///   - name: The name or id of the shortcut to run
        ///   - input: Optional input string to pass to the shortcut
        /// - Returns: Result message
        public func runShortcut(name: String, input: String? = nil) async -> String {
            await vxAtelierPro.log.debug("Running shortcut \(name) via CLI")
            
            // Method 1: Use the Shortcuts CLI (most reliable)
            let process = Process()
            let outputPipe = Pipe()
            
            // Escape the name for shell usage
            let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
            
            // Base arguments
            var arguments = ["run", escapedName]
            
            // Create a temporary file for input if needed
            var tempFileURL: URL? = nil
            if let input = input, !input.isEmpty {
                do {
                    // Create a temporary file for the input
                    let tempDir = FileManager.default.temporaryDirectory
                    tempFileURL = tempDir.appendingPathComponent(UUID().uuidString, isDirectory: false)
                    
                    // Write the input to the temporary file
                    try input.data(using: .utf8)?.write(to: tempFileURL!)
                    
                    // Add the input-path argument
                    arguments.append("--input-path")
                    arguments.append(tempFileURL!.path)
                    
                    await vxAtelierPro.log.debug("Created temp file for input at \(tempFileURL!.path)")
                } catch {
                    await vxAtelierPro.log.error("Failed to create temp file for input: \(error.localizedDescription)")
                    return "Failed to prepare input for shortcut: \(error.localizedDescription)"
                }
            }
            
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            do {
                await vxAtelierPro.log.debug("Running command: shortcuts \(arguments.joined(separator: " "))")
                try process.run()
                process.waitUntilExit()
                
                // Clean up the temporary file if we created one
                if let tempFileURL = tempFileURL {
                    try? FileManager.default.removeItem(at: tempFileURL)
                    await vxAtelierPro.log.debug("Removed temp input file")
                }
                
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    if process.terminationStatus == 0 {
                        await vxAtelierPro.log.debug("Successfully ran shortcut \(name)")
                        return "Shortcut '\(name)' ran successfully: \(output)"
                    } else {
                        await vxAtelierPro.log.error("Error running shortcut: \(output)")
                        return "Error running Shortcut '\(name)': \(output)"
                    }
                } else {
                    await vxAtelierPro.log.error("Failed to decode command output")
                    return "Failed to decode command output"
                }
            } catch {
                // Clean up the temporary file if we created one
                if let tempFileURL = tempFileURL {
                    try? FileManager.default.removeItem(at: tempFileURL)
                    await vxAtelierPro.log.debug("Removed temp input file after error")
                }
                
                await vxAtelierPro.log.error("Exception running shortcuts command: \(error.localizedDescription)")
                return "Failed to run shortcut: \(error.localizedDescription)"
            }
        }
    }
#endif
