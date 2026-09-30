import Foundation

struct ResetCredits: Codable, Hashable {
    let availableCount: Int
    let credits: [Credit]?
    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count", credits
    }
    struct Credit: Codable, Hashable, Identifiable {
        let id: String
        let status: String
        let title: String?
        var resetType: String? = nil
        var englishTitle: String {
            switch resetType {
            case "codex_rate_limits": return "Full reset"
            default: return "Usage reset"
            }
        }
        let expiresAt: String?
        enum CodingKeys: String, CodingKey {
            case id, status, title
            case resetType = "reset_type"
            case expiresAt = "expires_at"
        }
        var expiration: Date? {
            guard let expiresAt else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: expiresAt) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: expiresAt)
        }
    }
    var available: [Credit] { (credits ?? []).filter { $0.status == "available" } }
    var earliestExpiration: Date? { available.compactMap(\.expiration).min() }
}
