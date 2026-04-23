import Foundation

/// Shared port-cleanup helper used by OAuth callback servers.
///
/// A previous login attempt can leave a local listener bound (e.g. after a
/// crash or force-quit). Without cleanup, the next attempt fails with
/// EADDRINUSE. We find any process holding the TCP port via `lsof` and kill
/// it — SIGTERM first, then SIGKILL after a short grace period.
enum PortUtil {
    static func freePort(_ port: Int) {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", "tcp:\(port)"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        do {
            try lsof.run()
            lsof.waitUntilExit()
        } catch {
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let pids = (String(data: data, encoding: .utf8) ?? "")
            .split(whereSeparator: { $0.isNewline })
            .compactMap { Int32($0) }
        for pid in pids { kill(pid, SIGTERM) }
        if !pids.isEmpty { Thread.sleep(forTimeInterval: 0.5) }
        for pid in pids { kill(pid, SIGKILL) }
    }
}
