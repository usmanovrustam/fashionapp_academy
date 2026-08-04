import Foundation

/// User-selected gender for styling / outfit composition (e.g. dress looks).
enum UserGender: String, Codable, CaseIterable, Identifiable, Hashable {
    case woman
    case man
    case preferNotToSay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .woman: return NSLocalizedString("Woman", comment: "Gender option")
        case .man: return NSLocalizedString("Man", comment: "Gender option")
        case .preferNotToSay: return NSLocalizedString("Prefer not to say", comment: "Gender option")
        }
    }
}
