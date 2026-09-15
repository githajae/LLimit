# LLimit

Native macOS menu-bar app (SwiftUI + AppKit) that shows Claude Code, Codex, and Cursor CLI usage windows across multiple accounts.

Requires macOS 14+ and Xcode 15 / Swift 5.9. Apple Silicon is the supported install target; `Scripts/package_app.sh` builds universal when full Xcode is present.

## Layout

- `Sources/LLimit/App.swift` — `MenuBarExtra` + Settings scenes
- `Sources/LLimit/Models/` — `Account`, `Provider`, `UsageSnapshot`
- `Sources/LLimit/Services/` — auth, usage fetch, keychain, refresh, notifications
- `Sources/LLimit/Views/` — menu bar, popover, settings, login
- `Scripts/package_app.sh` — assemble `build/release/LLimit.app`
- `Scripts/release.sh` — tag + GitHub release
- `Scripts/test_security.sh` — grep-based security/correctness checks
- `website/` — static landing page

Bundle id is `com.githajae.llimit`. Credentials live under `~/Library/Application Support/LLimit/` (legacy dirs `LLMBar` / `LLMUsageTracker` are migrated once).

## Commands

```sh
swift build
Scripts/test_security.sh
Scripts/package_app.sh                  # → build/release/LLimit.app
Scripts/package_app.sh 0.2.0 zip        # versioned zip
Scripts/release.sh 0.2.0 "notes"        # maintainers only
Scripts/capture_readme_screenshot.sh    # simulated popover → Resources/screenshot.png
```

## Rules

- Keep Claude, Codex, and Cursor auth isolated per account. Claude and Cursor snapshots go to `credentials/<uuid>.json`; Codex uses a per-account `CODEX_HOME`. Cursor CLI tokens live in the `cursor-access-token` / `cursor-refresh-token` keychain items. Do not share one keychain token across multiple Claude or Cursor accounts.
- Persist `accounts.json` and credential files at `0o600`; credential directories at `0o700`.
- Never log tokens, PKCE verifiers, auth-URL query strings, or request bodies. `Scripts/test_security.sh` fails the build if those return.
- External HTTP is HTTPS only. Claude usage is `GET https://api.anthropic.com/api/oauth/usage`. Cursor usage is `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` with the CLI bearer. Build org-scoped URLs with `URLComponents`, not string interpolation.
- Claude login is PKCE S256 with `SecRandomCopyBytes` / CryptoKit and a validated `state`. Callback host is localhost.
- Do not send usage data anywhere except the Anthropic OAuth usage endpoint the Claude CLI already uses.
- Views stay dumb. Observable state lives in `AccountStore` and `RefreshCoordinator`.
- Match existing Swift style: `final class` + `@MainActor` for stores, `Codable` value types for models, no new third-party packages unless required.

## Cursor Cloud specific instructions

Cloud agents run on Linux and cannot compile or launch this AppKit/SwiftUI app. Do not run `swift build`, `package_app.sh`, or `open`. Edit source, keep `Scripts/test_security.sh` passing on the grep checks, and leave local Mac verification for the user.
