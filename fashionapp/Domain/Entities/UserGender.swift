import Foundation

/// User-selected gender for styling / outfit composition (e.g. dress looks).
enum UserGender: String, Codable, CaseIterable, Identifiable, Hashable {
    case woman
    case man

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .woman: return NSLocalizedString("Woman", comment: "Gender option")
        case .man: return NSLocalizedString("Man", comment: "Gender option")
        }
    }
}
