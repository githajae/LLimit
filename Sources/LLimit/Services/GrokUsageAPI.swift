import Foundation

// MARK: - Grok

/// Reads the Grok CLI's own sign-in (`<GROK_HOME>/auth.json`) and calls the
/// billing endpoint behind the CLI's `/usage` command.
///
/// LLimit never refreshes or rewrites that credential itself: the CLI owns
/// it, and rotating its refresh token from here could sign the CLI out. When
/// the access token has expired, LLimit runs `grok models`, which makes the
/// CLI refresh its own sign-in, and then reads the file again.
struct GrokUsageAPI: UsageAPI {
    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    static var defaultHome: String { NSHomeDirectory() + "/.grok" }

    enum GrokError: LocalizedError {
        case notSignedIn
        case expired
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in — run `grok login` in Terminal"
            case .expired: return "Not signed in — Grok sign-in expired; run `grok` once"
            case .http(let status): return "Grok usage request failed (HTTP \(status))"
            }
        }
    }

    func fetch(account: Account) async throws -> UsageSnapshot {
        let home = account.configDir
        var auth = try Self.loadAuth(home: home)
        if auth.expiresSoon {
            await Self.refreshViaCLI(home: home)
            auth = try Self.loadAuth(home: home)
            guard !auth.expiresSoon else { throw GrokError.expired }
        }

        let billing: BillingResponse
        do {
            billing = try await Self.fetchBilling(token: auth.token)
        } catch GrokError.http(401) {
            // The server can invalidate a token before its stated expiry.
            await Self.refreshViaCLI(home: home)
            auth = try Self.loadAuth(home: home)
            billing = try await Self.fetchBilling(token: auth.token)
        }
        return billing.snapshot(email: auth.email)
    }

    // MARK: Auth

    struct Auth {
        let token: String
        let email: String?
        let expiresAt: Date?

        var expiresSoon: Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSinceNow < 120
        }
    }

    /// `auth.json` maps `<issuer>::<id>` to a credential entry. Use the entry
    /// with a token that stays valid the longest.
    static func loadAuth(home: String) throws -> Auth {
        let url = URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url) else { throw GrokError.notSignedIn }
        return try parseAuth(data)
    }

    static func parseAuth(_ data: Data) throws -> Auth {
        struct Entry: Decodable {
            let key: String?
            let email: String?
            let expires_at: String?
        }
        guard let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            throw GrokError.notSignedIn
        }
        let candidates = entries.values.compactMap { entry -> Auth? in
            guard let key = entry.key, !key.isEmpty else { return nil }
            return Auth(token: key, email: entry.email, expiresAt: entry.expires_at.flatMap(parseDate))
        }
        guard let best = candidates.max(by: {
            ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast)
        }) else {
            throw GrokError.notSignedIn
        }
        return best
    }

    static func refreshViaCLI(home: String) async {
        guard let binary = await CLILoginRunner.resolveBinary("grok") else { return }
        var environment = CLIEnvironment.make(binaryPath: binary)
        if URL(fileURLWithPath: home).standardizedFileURL != URL(fileURLWithPath: defaultHome).standardizedFileURL {
            environment["GROK_HOME"] = home
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = ["models"]
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume()
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                    if process.isRunning { process.terminate() }
                }
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    // MARK: Billing

    static func fetchBilling(token: String) async throws -> BillingResponse {
        var request = URLRequest(url: billingURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("grok-cli/1.0.77 (LLimit)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw GrokError.http(status) }
        do {
            return try JSONDecoder().decode(BillingResponse.self, from: data)
        } catch {
            throw UsageAPIError.parse("Grok billing: \(error.localizedDescription)")
        }
    }

    struct BillingResponse: Decodable {
        let config: Config

        struct Config: Decodable {
            let currentPeriod: Period?
            let creditUsagePercent: Double?
            let productUsage: [Product]?
            let billingPeriodEnd: String?
        }

        struct Period: Decodable {
            let type: String?
            let start: String?
            let end: String?
        }

        struct Product: Decodable {
            let product: String
            let usagePercent: Double?
        }

        func snapshot(email: String?, fetchedAt: Date = Date()) -> UsageSnapshot {
            var windows: [UsageWindow] = []
            if let percent = config.creditUsagePercent {
                windows.append(UsageWindow(
                    label: Self.label(forPeriodType: config.currentPeriod?.type),
                    usedPercent: percent / 100,
                    resetsAt: (config.currentPeriod?.end ?? config.billingPeriodEnd).flatMap(GrokUsageAPI.parseDate)
                ))
            }
            return UsageSnapshot(
                fetchedAt: fetchedAt,
                windows: windows,
                note: productNote,
                email: email,
                planLabel: nil,
                organization: nil
            )
        }

        /// Share of the credit pool each Grok product used, e.g.
        /// "Build 11% · Chat 2%".
        var productNote: String? {
            let parts = (config.productUsage ?? []).compactMap { product -> String? in
                guard let percent = product.usagePercent else { return nil }
                return "\(Self.productName(product.product)) \(Int(percent.rounded()))%"
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        static func label(forPeriodType type: String?) -> String {
            switch type {
            case "USAGE_PERIOD_TYPE_DAILY": return "1d"
            case "USAGE_PERIOD_TYPE_MONTHLY": return "Monthly"
            default: return "7d"
            }
        }

        static func productName(_ raw: String) -> String {
            let trimmed = raw.hasPrefix("Grok") && raw.count > 4 ? String(raw.dropFirst(4)) : raw
            return trimmed.isEmpty ? raw : trimmed
        }
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
