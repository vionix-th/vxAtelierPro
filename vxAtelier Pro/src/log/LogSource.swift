import Foundation

struct LogSource: Hashable, Codable, Identifiable {
    let file: String
    let function: String
    var id: String { "\(file):\(function)" }
} 