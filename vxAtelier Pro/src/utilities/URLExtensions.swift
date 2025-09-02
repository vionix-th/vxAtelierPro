import Foundation

extension URLComponents {
    /// Returns a new URLComponents instance with the path appended.
    /// - Parameter path: The path to append
    /// - Returns: A new URLComponents instance with the path appended
    func appendingPath(_ path: String) -> URLComponents {
        var components = self
        var updatedPath = components.path
        
        // Ensure path starts with a slash
        if !path.hasPrefix("/") && !updatedPath.hasSuffix("/") {
            updatedPath += "/"
        }
        
        // Append the path
        updatedPath += path
        components.path = updatedPath
        
        return components
    }
} 