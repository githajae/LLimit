import SwiftUI
import AppKit

struct LoginSheet: View {
    let account: Account
    var store: AccountStore? = nil
    var onFinished: (() -> Void)? = nil

    @StateObject private var runner = CLILoginRunner()
    @Environment(\.dismiss) private var dismiss
    @State private var detectedLogin = false
    @State private var codeInput = ""

    @State private var oauthStatus: OAuthStatus = .idle
    @State private var oauthSession: ClaudeOAuthSession?

    enum OAuthStatus: Equatable {
        case idle
        case waiting        // browser opened, waiting on callback
        case exchanging     // got code, posting to token endpoint
        case validating     // token saved, verifying via profile API
        case done
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign in: \(account.name)").font(.headline)
                Text("\(account.provider.displayName) · \(account.configDir)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            if account.provider == .claude {
                claudeOAuthBody
            } else {
                codexBody
            }
        }
        .frame(width: 520)
        .onAppear {
            if account.provider == .codex { startLogin() }
        }
        .onChange(of: runner.status) { _, new in
            guard account.provider == .codex,
                  case .succeeded = new, !detectedLogin else { return }
            detectedLogin = true
            onFinished?()
            dismiss()
        }
    }

    // MARK: - Claude: PKCE OAuth in user's real browser

    @ViewBuilder
    private var claudeOAuthBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Click the button to open Claude's sign-in page in your browser. After you finish signing in, the browser will redirect back and the token will be saved here.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Each account stored independently — sign out of claude.ai between accounts (or use a different browser profile) so you can sign into the next one.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(action: startOAuth) {
                    Label(buttonTitle, systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInFlight)

                if isInFlight {
                    ProgressView().controlSize(.small)
                    // Validation is a synchronous API call; don't show Cancel
                    // for it — canceling mid-validation would leave the token
                    // saved but unverified, muddling the state.
                    if oauthStatus != .validating {
                        Button("Cancel sign-in") { cancelOAuth() }
                            .controlSize(.small)
                    }
                }
            }

            oauthStatusLabel
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)

        Divider()
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel") {
                cancelOAuth()
                dismiss()
            }
        }
        .padding(12)
    }

    private var isInFlight: Bool {
        switch oauthStatus {
        case .waiting, .exchanging, .validating: return true
        default: return false
        }
    }

    private var buttonTitle: String {
        switch oauthStatus {
        case .idle, .failed: return "Sign in to Claude"
        case .waiting: return "Waiting in browser…"
        case .exchanging: return "Finishing sign-in…"
        case .validating: return "Verifying token…"
        case .done: return "Done"
        }
    }

    @ViewBuilder
    private var oauthStatusLabel: some View {
        switch oauthStatus {
        case .idle:
            EmptyView()
        case .waiting:
            Text("Browser opened. Sign in there — this window will update automatically.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .exchanging:
            Text("Exchanging authorization code…")
                .font(.caption).foregroundStyle(.secondary)
        case .validating:
            Text("Verifying token with Anthropic…")
                .font(.caption).foregroundStyle(.secondary)
        case .done:
            Label("Saved.", systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startOAuth() {
        // Hard guard: SwiftUI's `disabled` modifier only suppresses paint, not
        // the action — fast double-clicks can dispatch twice before the first
        // `oauthStatus = .waiting` assignment is observed. Spawning two flows
        // means two listeners on two ports and (worse) two browser windows
        // racing the same authorization code.
        guard !isInFlight else {
            FileHandle.standardError.write(Data("[oauth] startOAuth: ignored (already in flight, status=\(oauthStatus))\n".utf8))
            return
        }
        let session = ClaudeOAuthSession()
        oauthSession = session
        oauthStatus = .waiting
        let acctId = account.id
        // MUST be a `Task { @MainActor }`, not `Task.detached`. A detached
        // task captures the View struct by value — the @State wrapper inside
        // the captured copy points to a different storage box than the live
        // view's, so `oauthStatus = .done` and `dismiss()` from a detached
        // task silently no-op. URLSession's awaits release the main thread,
        // so running on @MainActor doesn't block UI.
        Task { @MainActor in
            await LoginGate.shared.enter(acctId)
            defer { Task { await LoginGate.shared.leave(acctId) } }
            var savedSnapshot = false
            do {
                let token = try await ClaudeOAuthLogin.run(session: session)
                oauthStatus = .exchanging
                try ClaudeAuthSource.saveOAuth(
                    accessToken: token.accessToken,
                    refreshToken: token.refreshToken,
                    expiresIn: token.expiresIn,
                    for: acctId
                )
                savedSnapshot = true

                // Verify the token actually works before telling the user
                // "Saved." A 200 from /api/oauth/profile confirms the token
                // is live and the account is active. If this fails, the
                // saved snapshot is useless — delete it so we don't leave
                // a bogus "Signed in" state for next app launch.
                oauthStatus = .validating
                _ = try await AnthropicUsageAPI.fetchProfile(token: token.accessToken)

                oauthStatus = .done
                oauthSession = nil
                onFinished?()
                dismiss()
            } catch is CancellationError {
                // User-initiated abort (Cancel button or sheet dismiss).
                // Reset to idle so Sign in is clickable again.
                oauthStatus = .idle
                oauthSession = nil
            } catch {
                // If validation failed after the snapshot was written,
                // roll back so the UI isn't misleading on next open.
                if savedSnapshot, case .validating = oauthStatus {
                    ClaudeAuthSource.deleteSnapshot(for: acctId)
                }
                FileHandle.standardError.write(Data("[oauth] failed: \(error)\n".utf8))
                oauthStatus = .failed(error.localizedDescription)
                oauthSession = nil
            }
        }
    }

    private func cancelOAuth() {
        guard let session = oauthSession else { return }
        Task { await session.cancel() }
    }

    // MARK: - Codex: existing in-app CLI flow

    @ViewBuilder
    private var codexBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            inAppLoginUI
            HStack {
                Button("Restart") {
                    runner.cancel()
                    startLogin()
                }
                .controlSize(.small)
                Spacer()
                Button("Cancel") {
                    runner.cancel()
                    dismiss()
                }
                Button("Done") {
                    runner.cancel()
                    onFinished?()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var inAppLoginUI: some View {
        if let url = runner.detectedURL {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browser opened — sign in there.")
                        .font(.callout)
                    Button(url.absoluteString) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.10))
            )
        }

        if let prompt = runner.prompt {
            VStack(alignment: .leading, spacing: 6) {
                Text(prompt).font(.callout.weight(.medium))
                HStack {
                    TextField("paste here", text: $codeInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submitCode)
                    Button("Submit", action: submitCode)
                        .keyboardShortcut(.defaultAction)
                        .disabled(codeInput.isEmpty)
                }
            }
        }

        DisclosureGroup("Output") {
            ScrollView {
                Text(runner.output.isEmpty ? "(no output yet)" : runner.output)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(height: 140)
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }

        statusView
    }

    private func submitCode() {
        let trimmed = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runner.send(line: trimmed)
        codeInput = ""
    }

    private func startLogin() {
        runner.launch(account: account)
    }

    @ViewBuilder
    private var statusView: some View {
        if detectedLogin {
            Label("login detected — closing", systemImage: "checkmark.seal.fill")
                .font(.callout).foregroundStyle(.green)
        } else {
            switch runner.status {
            case .idle:
                EmptyView()
            case .running:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("waiting for sign-in to complete…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case .succeeded:
                Label("subprocess finished — verifying", systemImage: "hourglass")
                    .font(.callout).foregroundStyle(.secondary)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
            }
        }
    }
}
