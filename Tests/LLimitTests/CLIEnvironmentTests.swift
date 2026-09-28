import Foundation
import XCTest
@testable import LLimit

final class CLIEnvironmentTests: XCTestCase {
    func testEnvShebangFindsRuntimeBesideCLIWithFinderPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLimit CLI test \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Model an npm CLI: the CLI is found by absolute path, but its
        // /usr/bin/env shebang must also find a runtime installed beside it.
        let cli = directory.appendingPathComponent("test-cli")
        let runtime = directory.appendingPathComponent("llimit-test-runtime")
        try "#!/usr/bin/env llimit-test-runtime\n".write(to: cli, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nprintf 'runtime-ready'\n".write(to: runtime, atomically: true, encoding: .utf8)
        for file in [cli, runtime] {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }

        let process = Process()
        process.executableURL = cli
        process.environment = CLIEnvironment.make(
            binaryPath: cli.path,
            inherited: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        )
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "runtime-ready")
    }

    func testPreservesAccountEnvironmentAndCustomPathOrder() {
        let inherited = [
            "PATH": "/custom/first:/custom/second:/usr/bin:/opt/homebrew/bin",
            "CODEX_HOME": "/accounts/codex-3",
            "CLAUDE_CONFIG_DIR": "/accounts/claude",
            "TERM": "xterm-256color"
        ]
        let environment = CLIEnvironment.make(binaryPath: "/opt/homebrew/bin/codex", inherited: inherited)
        for key in ["CODEX_HOME", "CLAUDE_CONFIG_DIR", "TERM"] {
            XCTAssertEqual(environment[key], inherited[key])
        }
        let paths = environment["PATH", default: ""].components(separatedBy: ":")
        XCTAssertEqual(paths.first, "/opt/homebrew/bin")
        XCTAssertLessThan(paths.firstIndex(of: "/custom/first")!, paths.firstIndex(of: "/custom/second")!)
        XCTAssertEqual(paths.filter { $0 == "/opt/homebrew/bin" }.count, 1)
    }

    func testProvidesRuntimeAndSystemPathsWhenPathIsMissing() {
        let environment = CLIEnvironment.make(binaryPath: "/custom/bin/codex", inherited: [:])
        let paths = environment["PATH", default: ""].components(separatedBy: ":")
        for path in ["/custom/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            XCTAssertTrue(paths.contains(path), "Missing \(path)")
        }
        XCTAssertFalse(paths.contains(""))
    }
}
