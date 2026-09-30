import Foundation

struct UsageWindow: Codable, Hashable {
    var label: String
    var usedPercent: Double?
    var tokens: Int?
    var resetsAt: Date?
}

struct UsageSnapshot: Codable, Hashable {
    var fetchedAt: Date
    var windows: [UsageWindow]
    var note: String?
    var email: String?
    var planLabel: String?
    var organization: String?
    var resetCredits: ResetCredits? = nil
}

enum UsageState {
    case idle
    case loading
    case loaded(UsageSnapshot)
    case error(String)
}

extension UsageSnapshot {
    private var claudeWeeklyWindows: [UsageWindow] {
        windows.filter { $0.label == "7d" || $0.label.hasPrefix("Weekly · ") }
    }

    var claudeSummaryWindows: [UsageWindow] {
        var result = windows.filter { $0.label == "5h" }
        if var limiting = claudeWeeklyWindows.filter({ $0.usedPercent != nil })
            .max(by: { ($0.usedPercent ?? 0) < ($1.usedPercent ?? 0) }) {
            limiting.label = "7d"
            result.append(limiting)
        }
        return result
    }

    var claudeWeeklyHelp: String {
        let details = claudeWeeklyWindows.map { window in
            let name = window.label == "7d" ? "All models" : window.label.replacingOccurrences(of: "Weekly · ", with: "")
            guard let used = window.usedPercent else { return "\(name) unavailable" }
            return "\(name) \(Int((max(0, min(1, 1 - used)) * 100).rounded()))%"
        }
        return "Weekly remaining · " + details.joined(separator: " · ")
    }
}
