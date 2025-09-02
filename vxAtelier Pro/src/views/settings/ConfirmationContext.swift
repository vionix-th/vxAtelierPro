import Foundation

// MARK: - Confirmation Context
enum ConfirmationContext {
    case resetToDefaults
    case cleanLocalStorage
    case deleteAllModels
    case restoreDatabase
    
    var title: String {
        switch self {
        case .resetToDefaults: return "Reset to Defaults"
        case .cleanLocalStorage: return "Clear Local Storage"
        case .deleteAllModels: return "Delete All Models"
        case .restoreDatabase: return "Restore Database"
        }
    }
    
    var message: String {
        switch self {
        case .resetToDefaults: return "Are you sure you want to reset all settings to their default values?"
        case .cleanLocalStorage: return "Are you sure you want to clear all local storage? This action cannot be undone."
        case .deleteAllModels: return "Are you sure you want to delete all models? This action cannot be undone."
        case .restoreDatabase: return "Are you sure you want to restore the database? This action cannot be undone."
        }
    }
    
    var confirmButtonTitle: String {
        switch self {
        case .resetToDefaults: return "Reset"
        case .cleanLocalStorage: return "Clear"
        case .deleteAllModels: return "Delete"
        case .restoreDatabase: return "Restore"
        }
    }
} 