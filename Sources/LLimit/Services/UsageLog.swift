import Foundation

/// One line of `usage_log.jsonl`: every account's usage at one refresh.
struct UsageLogRecord: Codable, Hashable {
    let time: Date
    let accounts: [AccountUsage]

    struct AccountUsage: Codable, Hashable {
        let id: UUID
        let name: String
        let provider: Provider
        var fetchedAt: Date? = nil
        var windows: [Window]? = nil
        /// Available reset credits, when the provider reports them.
        var resets: Int? = nil
        var note: String? = nil
        var error: String? = nil
    }

    struct Window: Codable, Hashable {
        let label: String
        /// Percent of the limit used, 0–100.
        let usedPercent: Double?
        let resetsAt: Date?
    }
}

/// Append-only usage history at
/// `~/Library/Application Support/LLimit/usage_log.jsonl`, one JSON object
/// per refresh. The file is never trimmed.
@MainActor
final class UsageLog: ObservableObject {
    static let shared = UsageLog()

    /// Records read from disk plus everything appended since; populated by
    /// `loadIfNeeded()` (only the dashboard needs them).
    @Published private(set) var records: [UsageLogRecord] = []
    @Published private(set) var isLoaded = false

    private var loading = false
    private var appendedWhileLoading: [UsageLogRecord] = []

    nonisolated static var fileURL: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("LLimit", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage_log.jsonl")
    }

    nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Builds the record for one refresh. Accounts that kept an older
    /// snapshot after a transient failure are left out so the same reading
    /// is not logged twice.
    nonisolated static func record(time: Date, refreshStartedAt: Date,
                       accounts: [Account], states: [UUID: UsageState]) -> UsageLogRecord? {
        let entries = accounts.compactMap { account -> UsageLogRecord.AccountUsage? in
            var entry = UsageLogRecord.AccountUsage(id: account.id, name: account.name, provider: account.provider)
            switch states[account.id] {
            case .loaded(let snapshot) where snapshot.fetchedAt >= refreshStartedAt:
                entry.fetchedAt = snapshot.fetchedAt
                entry.windows = snapshot.windows.map { window in
                    UsageLogRecord.Window(
                        label: window.label,
                        usedPercent: window.usedPercent.map { ($0 * 10_000).rounded() / 100 },
                        resetsAt: window.resetsAt
                    )
                }
                entry.resets = snapshot.resetCredits?.availableCount
                entry.note = snapshot.note
                return entry
            case .error(let message):
                entry.error = message
                return entry
            default:
                return nil
            }
        }
        return entries.isEmpty ? nil : UsageLogRecord(time: time, accounts: entries)
    }

    func append(_ record: UsageLogRecord) {
        guard var line = try? Self.encoder().encode(record) else { return }
        line.append(0x0A)
        let url = Self.fileURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            FileHandle.standardError.write(Data("[usage-log] append failed: \(error)\n".utf8))
            return
        }
        if isLoaded {
            records.append(record)
        } else if loading {
            appendedWhileLoading.append(record)
        }
    }

    func loadIfNeeded() {
        guard !isLoaded, !loading else { return }
        loading = true
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { Self.readAll() }.value
            let lastTime = loaded.last?.time ?? .distantPast
            records = loaded + appendedWhileLoading.filter { $0.time > lastTime }
            appendedWhileLoading = []
            loading = false
            isLoaded = true
        }
    }

    nonisolated static func readAll() -> [UsageLogRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = decoder()
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(UsageLogRecord.self, from: Data(line))
        }
    }
}
