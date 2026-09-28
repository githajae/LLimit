import Foundation

/// LLimit owns a separate CODEX_HOME for each account. Legacy CLI homes are
/// read only during migration; never use them to log in or fetch usage again.
struct CodexCredentialStore {
    static let shared = CodexCredentialStore(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LLimit/codex", isDirectory: true))
    let root: URL

    func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func prepare(id: UUID) throws {
        let fm = FileManager.default
        for url in [root, directory(for: id)] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    func migrate(id: UUID, legacyDirectory: String) throws {
        try prepare(id: id)
        let fm = FileManager.default
        let destination = directory(for: id).appendingPathComponent("auth.json")
        let marker = directory(for: id).appendingPathComponent(".migration-v1")
        guard !fm.fileExists(atPath: marker.path) else { return }
        let source = URL(fileURLWithPath: legacyDirectory).appendingPathComponent("auth.json")
        if !fm.fileExists(atPath: destination.path), fm.fileExists(atPath: source.path) {
            // The private parent is mode 0700 even while the copy is in flight.
            try Data(contentsOf: source).write(to: destination, options: .atomic)
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        // Also mark missing-source accounts, so a later CLI login cannot bind
        // an existing LLimit account to a different identity unexpectedly.
        try Data().write(to: marker, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    }
}
