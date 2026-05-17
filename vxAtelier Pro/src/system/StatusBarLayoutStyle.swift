import Foundation

enum StatusBarLayoutStyle: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case singleRow = "Single Row"
    case twoRows = "Two Rows"

    var id: String { rawValue }
}
