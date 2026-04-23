import Foundation
import AppKit

/// Drives the `claude auth login` / `codex login` flows in-process so the
/// user never sees a Terminal pop open. We:
///   1. resolve the CLI binary
///   2. (codex only) free port 1455 if a stale callback server still holds it
///   3. spawn the CLI with pipes wired to our log buffer
///   4. stream every line into `output` and detect the OAuth URL
///   5. auto-open the URL in the user's browser
///   6. expose stdin so the user can paste a code (claude device-code flow)
///   7. signal `.succeeded` / `.failed` when the subprocess exits.
@MainActor
final class CLILoginRunner: ObservableObject {
    @Published var status: Status = .idle
    @Published var commandLine: String = ""
    @Published var output: String = ""
    @Published var detectedURL: URL?
    @Published var prompt: String?

    enum Status: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var currentProvider: Provider?

    func launch(account: Account) {
        cancel()
        currentProvider = account.provider
        let (binary, args, envKey) = command(for: account.provider)
        guard let binPath = Self.resolveBinary(binary) else {
            status = .failed("\(binary) not found in PATH")
            return
        }

        try? FileManager.default.createDirectory(
            atPath: account.configDir,
            withIntermediateDirectories: true
        )

        // Codex spins a local OAuth callback on port 1455. A previous,
        // half-dead login can keep the socket bound; free it before launching.
        if account.provider == .codex {
            PortUtil.freePort(1455)
        }

        commandLine = "\(envKey)=\(account.configDir) \(binPath) \(args.joined(separator: " "))"
        output = ""
        detectedURL = nil
        prompt = nil

        // The Codex login CLI only starts its localhost:1455 callback server
        // when stdin/stdout are real TTYs — pipes alone make it bail silently
        // and the browser hits ERR_CONNECTION_REFUSED. Wrap the command with
        // /usr/bin/script (BSD variant on macOS) so it sees a pty.
        let p = Process()
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/script") {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            p.arguments = ["-q", "/dev/null", binPath] + args
        } else {
            p.executableURL = URL(fileURLWithPath: binPath)
            p.arguments = args
        }
        var env = ProcessInfo.processInfo.environment
        env[envKey] = account.configDir
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        p.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = inPipe
        stdinHandle = inPipe.fileHandleForWriting

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                if proc.terminationStatus == 0 {
                    self.status = .succeeded
                } else {
                    self.status = .failed("exited with code \(proc.terminationStatus)")
                }
            }
        }

        do {
            try p.run()
            process = p
            status = .running
            attachReader(outPipe.fileHandleForReading)
            attachReader(errPipe.fileHandleForReading)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        stdinHandle = nil
    }

    func send(line: String) {
        guard let h = stdinHandle else { return }
        let data = (line + "\n").data(using: .utf8) ?? Data()
        try? h.write(contentsOf: data)
        prompt = nil
    }

    private func attachReader(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.ingest(chunk)
            }
        }
    }

    private func ingest(_ chunk: String) {
        output.append(chunk)
        // Cap to the last 8 KB so the View doesn't bog down on long sessions.
        if output.count > 8_192 {
            output = String(output.suffix(8_192))
        }

        if detectedURL == nil, let url = Self.firstURL(in: chunk) {
            detectedURL = url
            // Both `claude auth login` and `codex login` auto-open the
            // browser themselves. Calling NSWorkspace.shared.open here too
            // produces two Chrome windows. Leave the URL as a clickable
            // link in the sheet for the rare case auto-open fails.
        }

        // Claude's device-code prompt looks like "Paste code here: ".
        let trimmed = chunk
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if trimmed.contains("paste") && trimmed.contains("code") {
            prompt = "Paste the code from the browser:"
        }
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.firstMatch(in: text, range: range),
              let url = match.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private func command(for provider: Provider) -> (String, [String], String) {
        switch provider {
        case .claude:
            return ("claude", ["auth", "login"], "CLAUDE_CONFIG_DIR")
        case .codex:
            return ("codex", ["login"], "CODEX_HOME")
        }
    }

    static func resolveBinary(_ name: String) -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/Applications/cmux.app/Contents/Resources/bin/\(name)",
        ]
        for c in candidates
            where FileManager.default.isExecutableFile(atPath: c) && !isShellScript(c) {
            return c
        }
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-l", "-c", "command -v \(name)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    static func isShellScript(_ path: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        let head = fh.readData(ofLength: 2)
        return head == Data("#!".utf8)
    }

    static func isLoggedIn(account: Account) async -> Bool {
        switch account.provider {
        case .claude:
            let out = await runCapture("claude", ["auth", "status"], env: ["CLAUDE_CONFIG_DIR": account.configDir])
            struct S: Decodable { let loggedIn: Bool }
            if let data = out.data(using: .utf8),
               let s = try? JSONDecoder().decode(S.self, from: data) {
                return s.loggedIn
            }
            return false
        case .codex:
            let out = await runCapture("codex", ["login", "status"], env: ["CODEX_HOME": account.configDir])
            return out.lowercased().contains("logged in")
        }
    }

    static func runCapture(_ binary: String, _ args: [String], env: [String: String]) async -> String {
        guard let binPath = resolveBinary(binary) else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binPath)
        p.arguments = args
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        p.environment = environment
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do {
            try p.run()
        } catch {
            return ""
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global().async {
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                cont.resume(returning: out.isEmpty ? err : out)
            }
        }
    }
}
