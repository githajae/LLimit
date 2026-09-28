import Foundation

enum CLIEnvironment {
    static func make(
        binaryPath: String,
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = inherited
        // Finder/login-item launches have a minimal PATH. Resolving the CLI's
        // absolute path is not enough for npm's #!/usr/bin/env node launcher.
        // Keep the selected CLI's runtime first, then preserve inherited paths
        // and add common install locations without invoking shell startup files.
        let binaryDirectory = URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path
        let inheritedPaths = (inherited["PATH"] ?? "").split(separator: ":").map(String.init)
        let fallbackPaths = [
            "\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        var seen = Set<String>()
        environment["PATH"] = ([binaryDirectory] + inheritedPaths + fallbackPaths)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }
}
