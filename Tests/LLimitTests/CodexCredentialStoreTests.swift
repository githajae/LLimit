import Foundation
import XCTest
@testable import LLimit

final class CodexCredentialStoreTests: XCTestCase {
    func testMigrationCopiesOnceAndKeepsAccountsIndependent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("cli")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let original = Data("{\"tokens\":{\"access_token\":\"test-original\"}}".utf8)
        let auth = source.appendingPathComponent("auth.json")
        try original.write(to: auth)
        let first = UUID(), second = UUID()
        let store = CodexCredentialStore(root: root.appendingPathComponent("private"))
        try store.migrate(id: first, legacyDirectory: source.path)
        try store.migrate(id: second, legacyDirectory: source.path)
        let a = store.directory(for: first).appendingPathComponent("auth.json")
        let b = store.directory(for: second).appendingPathComponent("auth.json")
        XCTAssertEqual(try Data(contentsOf: a), original)
        XCTAssertEqual(try Data(contentsOf: b), original)
        try Data("changed-cli".utf8).write(to: auth)
        try store.migrate(id: first, legacyDirectory: source.path)
        XCTAssertEqual(try Data(contentsOf: a), original)
        try Data("changed-llimit".utf8).write(to: a)
        XCTAssertEqual(try Data(contentsOf: auth), Data("changed-cli".utf8))
        XCTAssertEqual(try Data(contentsOf: b), original)
        try FileManager.default.removeItem(at: a)
        try store.migrate(id: first, legacyDirectory: source.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path), "Never reimport after logout")
        let mode = try FileManager.default.attributesOfItem(atPath: b.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testExistingPrivateLoginWinsAndMissingSourceDoesNotBlock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexCredentialStore(root: root)
        let id = UUID()
        try store.prepare(id: id)
        let auth = store.directory(for: id).appendingPathComponent("auth.json")
        let data = Data("existing-private-login".utf8)
        try data.write(to: auth)
        try store.migrate(id: id, legacyDirectory: root.appendingPathComponent("missing").path)
        XCTAssertEqual(try Data(contentsOf: auth), data)
        try store.migrate(id: UUID(), legacyDirectory: root.appendingPathComponent("missing").path)
    }

    func testLegacySymlinkIsCopiedAsIndependentFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.json")
        try Data("original".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: legacy.appendingPathComponent("auth.json"), withDestinationURL: original)
        let store = CodexCredentialStore(root: root.appendingPathComponent("private"))
        let id = UUID()
        try store.migrate(id: id, legacyDirectory: legacy.path)
        let privateAuth = store.directory(for: id).appendingPathComponent("auth.json")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: privateAuth.path)[.type] as? FileAttributeType, .typeRegular)
        try Data("new-private-login".utf8).write(to: privateAuth)
        XCTAssertEqual(try Data(contentsOf: original), Data("original".utf8))
    }

    func testCodexPathDoesNotDependOnEditableConfigDir() {
        let id = UUID()
        let a = Account(id: id, name: "one", provider: .codex, configDir: "/legacy/a")
        let b = Account(id: id, name: "renamed", provider: .codex, configDir: "/legacy/b")
        XCTAssertEqual(a.authenticationDirectory, b.authenticationDirectory)
        XCTAssertNotEqual(a.authenticationDirectory, a.configDir)
        XCTAssertNotEqual(a.authenticationDirectory, Account(name: "two", provider: .codex, configDir: a.configDir).authenticationDirectory)
    }
}
