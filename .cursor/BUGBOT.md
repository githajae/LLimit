# Bugbot

Native macOS menu-bar app. Treat auth and credential handling as the high-risk surface.

## Must flag

- Tokens, PKCE verifiers, refresh tokens, or auth-URL query strings in logs, traces, or UI
- Credential files or `accounts.json` written without `0o600`, or credentials dir without `0o700`
- One Claude/Codex credential reused across accounts, or writing two accounts into the same `CODEX_HOME` / snapshot path
- Non-HTTPS URLs except localhost OAuth callback
- Org or account IDs concatenated into URLs instead of `URLComponents`
- Claude OAuth missing S256, secure random verifier, or `state` validation
- Hardcoded `sk-ant-`, `sk-` keys, or client secrets
- Sending usage payloads anywhere other than Anthropic's OAuth usage endpoint, Codex usage, or Cursor's dashboard usage API

## Ignore

- Ad-hoc codesign / Gatekeeper notes in `package_app.sh` and the README
- Linux Cloud Agent inability to `swift build` this AppKit target
