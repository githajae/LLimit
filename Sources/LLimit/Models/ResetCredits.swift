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
        /// Model a Claude reset is restricted to (for example "Fable"); not
        /// part of the Codex wire format.
        var modelName: String? = nil
        var englishTitle: String {
            if let modelName { return "\(modelName) reset" }
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

    /// Available credits collapsed by type and expiry day, soonest first, so
    /// three identical "Fable reset" grants read as one line with a count.
    var groups: [Group] {
        let calendar = Calendar.current
        var result: [Group] = []
        for credit in available {
            let day = credit.expiration.map { calendar.startOfDay(for: $0) }
            if let index = result.firstIndex(where: {
                $0.title == credit.englishTitle && $0.expirationDay == day
            }) {
                result[index].count += 1
                if let date = credit.expiration, date < (result[index].expiration ?? .distantFuture) {
                    result[index].expiration = date
                }
            } else {
                result.append(Group(title: credit.englishTitle, expiration: credit.expiration,
                                    expirationDay: day, count: 1))
            }
        }
        return result.sorted {
            ($0.expiration ?? .distantFuture, $0.title) < ($1.expiration ?? .distantFuture, $1.title)
        }
    }

    struct Group: Hashable, Identifiable {
        let title: String
        var expiration: Date?
        let expirationDay: Date?
        var count: Int
        var id: String { "\(title)|\(expirationDay?.timeIntervalSince1970 ?? -1)" }
    }
}
