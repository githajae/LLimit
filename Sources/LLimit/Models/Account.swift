import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        case .grok:   return "Grok"
        }
    }
}

struct Account: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var provider: Provider
    var authenticationDirectory: String {
        provider == .codex ? CodexCredentialStore.shared.directory(for: id).path : configDir
    }

    var configDir: String
}
