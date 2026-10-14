import Foundation

/// Read-only projection of Claude Code's optional `cedar_ember` usage block.
struct ClaudeResetStatus: Codable {
    let eligible: Bool
    let grants: [Grant]

    struct Grant: Codable {
        let id: String
        let label: String?
        let resets_left: Int
        let starts_at: String?
        let ends_at: String?
        let paused: Bool?
    }

    func resetCredits(now: Date = Date()) -> ResetCredits? {
        // Ineligibility can mean an unsupported client surface, not zero credits.
        guard eligible else { return nil }
        var credits: [ResetCredits.Credit] = []
        for grant in grants {
            guard grant.resets_left > 0, grant.paused != true else { continue }
            let template = ResetCredits.Credit(
                id: grant.id, status: "available", title: grant.label,
                expiresAt: grant.ends_at
            )
            if grant.ends_at != nil {
                guard let end = template.expiration, end > now else { continue }
            }
            if let start = grant.starts_at {
                let startCredit = ResetCredits.Credit(
                    id: grant.id, status: "available", title: nil, expiresAt: start
                )
                guard let date = startCredit.expiration, date <= now else { continue }
            }
            // A grant can contain several resets; the shared UI lists each credit.
            // A malformed count is unknown rather than an unbounded allocation.
            guard grant.resets_left <= 1000 else { return nil }
            for index in 0..<grant.resets_left {
                credits.append(ResetCredits.Credit(
                    id: "\(grant.id)-\(index)", status: "available",
                    title: grant.label, expiresAt: grant.ends_at
                ))
            }
        }
        return ResetCredits(availableCount: credits.count, credits: credits)
    }
}
