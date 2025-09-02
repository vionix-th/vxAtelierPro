import SwiftUI
import SwiftData
import OSLog

// MARK: - Error Types

/// Application-specific errors
enum AppError: LocalizedError {
    case modelContextMissing
    case dataFetchFailed(String)
    case dataSaveFailed(String)
    case invalidConfiguration(String)
    case networkError(String)
    case fileOperationFailed(String)
    case fileAccessError(String)
    case decodingFailed(String)
    case encodingFailed(String)
    case invalidArguments(String)
    case aiServiceError(String)
    case invalidOperation(String)
    
    var errorDescription: String? {
        switch self {
        case .modelContextMissing:
            return "Database context is not available"
        case .dataFetchFailed(let details):
            return "Failed to fetch data: \(details)"
        case .dataSaveFailed(let details):
            return "Failed to save data: \(details)"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .networkError(let details):
            return "Network error: \(details)"
        case .fileOperationFailed(let details):
            return "File operation failed: \(details)"
        case .fileAccessError(let details):
            return "File access error: \(details)"
        case .decodingFailed(let details):
            return "Failed to decode data: \(details)"
        case .encodingFailed(let details):
            return "Failed to encode data: \(details)"
        case .invalidArguments(let details):
            return "Invalid arguments: \(details)"
        case .aiServiceError(let details):
            return "AI service error: \(details)"
        case .invalidOperation(let details):
            return "Invalid operation: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .modelContextMissing:
            return "Try restarting the application"
        case .dataFetchFailed:
            return "Check your database connection and try again"
        case .dataSaveFailed:
            return "Ensure you have sufficient disk space and permissions"
        case .invalidConfiguration:
            return "Review your configuration settings"
        case .networkError:
            return "Check your internet connection and try again"
        case .fileOperationFailed, .fileAccessError:
            return "Ensure you have the necessary permissions and disk space"
        case .decodingFailed:
            return "The data format might be invalid or corrupted"
        case .encodingFailed:
            return "Check if all required fields are properly filled"
        case .invalidArguments:
            return "Check that all required arguments are provided and have valid values"
        case .aiServiceError:
            return "Check the AI service configuration and try again"
        case .invalidOperation:
            return "Check the operation and ensure it's valid for the given types"
        }
    }
}

// MARK: - Error Alert

/// Represents an error alert that can be presented to the user
struct ErrorAlert: Identifiable {
    let id = UUID()
    let error: Error
    var title: String
    var message: String
    var primaryButtonTitle: String
    var secondaryButtonTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryAction: (() -> Void)?
    
    init(error: Error,
         title: String? = nil,
         message: String? = nil,
         primaryButtonTitle: String = "OK",
         secondaryButtonTitle: String? = nil,
         primaryAction: (() -> Void)? = nil,
         secondaryAction: (() -> Void)? = nil) {
        self.error = error
        self.title = title ?? "Error"
        self.message = message ?? (error.localizedDescription + (((error as? LocalizedError)?.recoverySuggestion).map { "\n\n\($0)" } ?? ""))
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
}

// MARK: - Error Handling Extensions

extension View {
    /// Presents an error alert when an error is present
    func errorAlert(error: Binding<ErrorAlert?>) -> some View {
        alert(
            error.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            ),
            actions: {
                if let secondaryTitle = error.wrappedValue?.secondaryButtonTitle {
                    Button(secondaryTitle, role: .cancel) {
                        error.wrappedValue?.secondaryAction?()
                        error.wrappedValue = nil
                    }
                }
                Button(error.wrappedValue?.primaryButtonTitle ?? "OK") {
                    error.wrappedValue?.primaryAction?()
                    error.wrappedValue = nil
                }
            },
            message: {
                Text(error.wrappedValue?.message ?? "")
            }
        )
    }
}

// MARK: - JSON Error Handling

extension JSONDecoder {
    /// Decodes data with proper error handling
    func decodeWithErrorHandling<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decode(type, from: data)
        } catch {
            vxAtelierPro.log.error("Failed to decode \(T.self): \(error.localizedDescription)")
            throw AppError.decodingFailed(error.localizedDescription)
        }
    }
}

extension JSONEncoder {
    /// Encodes data with proper error handling
    func encodeWithErrorHandling<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encode(value)
        } catch {
            vxAtelierPro.log.error("Failed to encode \(T.self): \(error.localizedDescription)")
            throw AppError.encodingFailed(error.localizedDescription)
        }
    }
} 