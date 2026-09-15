import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        case .cursor: return "Cursor"
        }
    }
}

struct Account: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var provider: Provider
    var configDir: String
}
