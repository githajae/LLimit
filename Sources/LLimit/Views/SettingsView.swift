import SwiftUI
import AppKit

/// Unified login state for an account, combining on-disk credential checks
/// with the most recent API result from `RefreshCoordinator`.
///
/// Before, Settings used a file-only check and the popover used the API
/// result. They could disagree — e.g. file says "logged in" but the token
/// was already revoked server-side. `.tokenInvalid` reconciles the two: the
/// file exists, but the API told us it doesn't actually work.
enum LoginStatus: Equatable {
    case signedIn(email: String?)       // file present AND last API call succeeded
    case tokenInvalid(email: String?)   // file present but API returned 401/403
    case pending                        // file present, API not yet called
    case signedOut                      // no credential file

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    /// File-only read; used on the menu-bar hot path where we don't have a
    /// UsageState in scope. Returns either `.signedIn` or `.signedOut`.
    static func readFile(_ account: Account) -> LoginStatus {
        switch account.provider {
        case .claude:
            // Check LLimit's own per-account credential snapshot first.
            if ClaudeAuthSource.hasSnapshot(for: account.id) {
                if let bundle = try? ClaudeAuthSource(accountId: account.id).load(),
                   !bundle.accessToken.isEmpty {
                    return .signedIn(email: claudeEmailFromCLI(account))
                }
            }
            // Fall back to the CLI's .claude.json for email display.
            let path = account.configDir + "/.claude.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = root["oauthAccount"] as? [String: Any] else {
                return .signedOut
            }
            let email = oauth["emailAddress"] as? String
            return .signedIn(email: email)
        case .codex:
            let path = account.configDir + "/auth.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .signedOut
            }
            let tokens = root["tokens"] as? [String: Any]
            let hasToken = (tokens?["access_token"] as? String)?.isEmpty == false
                || (root["OPENAI_API_KEY"] as? String)?.isEmpty == false
            guard hasToken else { return .signedOut }
            return .signedIn(email: codexEmailFromIDToken(tokens))
        case .cursor:
            if CursorAuthSource.hasSnapshot(for: account.id) {
                return .signedIn(email: nil)
            }
            if CursorAuthSource.hasCLIKeychain() {
                return .signedIn(email: nil)
            }
            return .signedOut
        }
    }

    /// Combined view: cross-checks the file state with the most recent API
    /// result. If the file says "signed in" but the API returned a "not
    /// signed in"/auth error, we report `.tokenInvalid` instead.
    static func read(_ account: Account, usageState: UsageState) -> LoginStatus {
        let fileStatus = readFile(account)
        guard case .signedIn(let email) = fileStatus else { return .signedOut }

        switch usageState {
        case .loaded(let snap):
            return .signedIn(email: snap.email ?? email)
        case .error(let msg) where isAuthError(msg):
            return .tokenInvalid(email: email)
        case .idle, .loading, .error:
            // File says signed in but no confirmed-bad API result yet —
            // stay tentatively "signed in" so the row doesn't flicker on
            // every transient network error.
            return .signedIn(email: email)
        }
    }

    private static func isAuthError(_ msg: String) -> Bool {
        msg.contains("Not signed in") ||
        msg.contains("Login") ||
        msg.contains("HTTP 401") ||
        msg.contains("HTTP 403")
    }

    private static func claudeEmailFromCLI(_ account: Account) -> String? {
        let path = account.configDir + "/.claude.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["oauthAccount"] as? [String: Any] else {
            return nil
        }
        return oauth["emailAddress"] as? String
    }

    private static func codexEmailFromIDToken(_ tokens: [String: Any]?) -> String? {
        guard let idToken = tokens?["id_token"] as? String else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var s = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let d = Data(base64Encoded: s),
              let claims = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return nil
        }
        return claims["email"] as? String
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var refresher: RefreshCoordinator

    @State private var loginAccount: Account?

    var body: some View {
        TabView {
            AccountsTab(loginAccount: $loginAccount)
                .tabItem { Label("Accounts", systemImage: "person.2") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 620, height: 520)
        .sheet(item: $loginAccount) { account in
            LoginSheet(account: account, store: store) {
                Task { await refresher.refresh(account) }
            }
        }
    }
}

// MARK: - Accounts

private struct AccountsTab: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var refresher: RefreshCoordinator
    @Binding var loginAccount: Account?

    @State private var selection: UUID?
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable, Equatable {
        let id: UUID
        var account: Account
        var isAdding: Bool
    }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 200, maxWidth: 240)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selection) { _, new in loadEditing(for: new) }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.accounts) { acc in
                    HStack(spacing: 8) {
                        ProviderIcon(provider: acc.provider, size: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(acc.name).font(.body)
                            Text(acc.provider.displayName)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusDot(for: acc)
                    }
                    .tag(acc.id)
                }
                .onMove { from, to in
                    store.move(fromOffsets: from, toOffset: to)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Button {
                    startAdd()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    guard let id = selection,
                          let acc = store.accounts.first(where: { $0.id == id })
                    else { return }
                    selection = nil
                    editing = nil
                    refresher.forget(id)
                    store.remove(acc)
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selection == nil)
                Spacer()
                Button {
                    if let id = selection { store.move(id, by: -1) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!canMove(by: -1))
                Button {
                    if let id = selection { store.move(id, by: 1) }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(!canMove(by: 1))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(8)
        }
    }

    private func canMove(by delta: Int) -> Bool {
        guard let id = selection,
              let i = store.accounts.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let target = i + delta
        return target >= 0 && target < store.accounts.count
    }

    @ViewBuilder
    private func statusDot(for account: Account) -> some View {
        let status = LoginStatus.read(account, usageState: refresher.states[account.id] ?? .idle)
        switch status {
        case .signedIn:
            Circle().fill(Color.green).frame(width: 7, height: 7)
        case .tokenInvalid:
            Circle().fill(Color.orange).frame(width: 7, height: 7)
        case .pending:
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
        case .signedOut:
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let target = editing {
            EditForm(
                initial: target.account,
                isAdding: target.isAdding,
                usageState: refresher.states[target.id] ?? .idle,
                existingConfigDirs: Set(store.accounts.map(\.configDir)),
                onSave: { updated in save(updated, wasAdding: target.isAdding) },
                onCancel: { editing = nil },
                onLogin: { acc in loginAccount = acc }
            )
            .id(target.id)
            .padding()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Select an account or click + to add one")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func startAdd() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let base = home + "/.claude"
        let acc = Account(name: "", provider: .claude,
                          configDir: uniqueDir(from: base))
        selection = nil
        editing = EditTarget(id: acc.id, account: acc, isAdding: true)
    }

    private func uniqueDir(from base: String) -> String {
        EditForm.uniqueDir(from: base, excluding: Set(store.accounts.map(\.configDir)))
    }

    private func save(_ incoming: Account, wasAdding: Bool) {
        var d = incoming
        if d.name.trimmingCharacters(in: .whitespaces).isEmpty {
            d.name = "\(d.provider.displayName) (\(URL(fileURLWithPath: d.configDir).lastPathComponent))"
        }
        editing = nil
        selection = nil
        if wasAdding {
            store.add(d)
        } else {
            store.update(d)
        }
        selection = d.id
        Task { await refresher.refresh(d) }
    }

    private func loadEditing(for id: UUID?) {
        guard let id, let acc = store.accounts.first(where: { $0.id == id }) else {
            if editing?.isAdding != true { editing = nil }
            return
        }
        editing = EditTarget(id: acc.id, account: acc, isAdding: false)
    }

}

private struct EditForm: View {
    @State private var draft: Account
    let isAdding: Bool
    let usageState: UsageState
    let existingConfigDirs: Set<String>
    let onSave: (Account) -> Void
    let onCancel: () -> Void
    let onLogin: (Account) -> Void

    init(initial: Account,
         isAdding: Bool,
         usageState: UsageState = .idle,
         existingConfigDirs: Set<String> = [],
         onSave: @escaping (Account) -> Void,
         onCancel: @escaping () -> Void,
         onLogin: @escaping (Account) -> Void) {
        _draft = State(initialValue: initial)
        self.isAdding = isAdding
        self.usageState = usageState
        self.existingConfigDirs = existingConfigDirs
        self.onSave = onSave
        self.onCancel = onCancel
        self.onLogin = onLogin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isAdding ? "New account" : "Edit account")
                .font(.headline)

            Form {
                TextField("Name", text: $draft.name,
                          prompt: Text("e.g. Work Claude"))
                Picker("Provider", selection: $draft.provider) {
                    ForEach(Provider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.provider) { _, p in
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    let suffix: String
                    switch p {
                    case .claude: suffix = "/.claude"
                    case .codex: suffix = "/.codex"
                    case .cursor: suffix = "/.cursor"
                    }
                    draft.configDir = Self.uniqueDir(from: home + suffix, excluding: existingConfigDirs)
                }
                HStack {
                    TextField("Config dir", text: $draft.configDir,
                              prompt: Text("~/.claude"))
                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            draft.configDir = url.path
                        }
                    }
                }
            }

            if !isAdding {
                loginStatusRow
            }

            Spacer()

            HStack {
                if !isAdding {
                    Button("Login…") { onLogin(draft) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                Button(isAdding ? "Add" : "Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidConfigDir(draft.configDir))
            }
        }
    }

    static func uniqueDir(from base: String, excluding inUse: Set<String>) -> String {
        if !inUse.contains(base) { return base }
        for n in 2...20 {
            let candidate = "\(base)-\(n)"
            if !inUse.contains(candidate) { return candidate }
        }
        return base
    }

    private func isValidConfigDir(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // Must be an absolute path under the user's home directory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return trimmed.hasPrefix(home) || trimmed.hasPrefix("/Users/")
    }

    @ViewBuilder
    private var loginStatusRow: some View {
        let status = LoginStatus.read(draft, usageState: usageState)
        HStack(spacing: 6) {
            switch status {
            case .signedIn(let email):
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                if let email {
                    Text("Signed in as \(email)")
                        .font(.callout)
                } else {
                    Text("Signed in")
                        .font(.callout)
                }
            case .tokenInvalid:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Token expired — sign in again")
                    .font(.callout)
                    .foregroundStyle(.orange)
            case .pending:
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .signedOut:
                Image(systemName: "xmark.seal")
                    .foregroundStyle(.secondary)
                Text("Not signed in")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var refresher: RefreshCoordinator

    @AppStorage("warnAtPercent") private var warnAtPercent: Double = 80
    @AppStorage("showResetTimes") private var showResetTimes: Bool = true
    @AppStorage("compactMenuBar") private var compactMenuBar: Bool = false
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Refresh") {
                Stepper(value: Binding(
                    get: { store.pollIntervalSeconds / 60 },
                    set: { store.setPollInterval($0 * 60) }
                ), in: 1...120) {
                    HStack {
                        Text("Auto-refresh every")
                        Text("\(store.pollIntervalSeconds / 60) min")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button {
                        Task { await refresher.refreshAll() }
                    } label: {
                        Label("Refresh now", systemImage: "arrow.clockwise")
                    }
                    if let last = refresher.lastRefreshedAt {
                        Text("last: \(last, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Display") {
                Toggle("Show reset times under each bar", isOn: $showResetTimes)
                Toggle("Compact menu bar (icon only)", isOn: $compactMenuBar)
                LabeledContent("Warn at") {
                    HStack {
                        Slider(value: $warnAtPercent, in: 50...95, step: 5)
                            .frame(maxWidth: 200)
                        Text("\(Int(warnAtPercent))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { v in launchAtLogin = v; LaunchAtLogin.setEnabled(v) }
                ))
            }

            Section("Storage") {
                LabeledContent("Config") {
                    Text(configPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(configPath, inFileViewerRootedAtPath: "")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var configPath: String {
        let fm = FileManager.default
        let url = (try? fm.url(for: .applicationSupportDirectory,
                               in: .userDomainMask, appropriateFor: nil, create: false))?
            .appendingPathComponent("LLimit/accounts.json")
        return url?.path ?? "~/Library/Application Support/LLimit/accounts.json"
    }
}
