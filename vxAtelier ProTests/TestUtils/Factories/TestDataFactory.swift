import Foundation
#if canImport(vxAtelier_Pro_debug)
@testable import vxAtelier_Pro_debug
#else
@testable import vxAtelier_Pro
#endif

/// Protocol defining the interface for test data factories
protocol TestDataFactory {
    associatedtype Model
    
    /// Creates a model instance with default test values
    func create() -> Model
    
    /// Creates a model instance with specified overrides
    func create(overrides: (inout Model) -> Void) -> Model
}

/// Base class for test data factories that provides common functionality
class BaseTestFactory<T> {
    /// Generates a unique identifier for test data
    func uniqueIdentifier() -> String {
        return UUID().uuidString
    }
    
    /// Generates a timestamp within the last 24 hours
    func recentTimestamp() -> Date {
        return Date().addingTimeInterval(-Double.random(in: 0...(24 * 60 * 60)))
    }
}
