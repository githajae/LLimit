import Foundation
import Combine

/// Tracks accounts with an in-progress login so auto-refresh doesn't race
/// the credential write and replace the new state with a stale "Not signed
/// in" error from reading the file mid-write.
///
/// LoginSheet (Claude OAuth) and CLILoginRunner (Codex) call enter() before
/// starting auth and leave() in the finally path. RefreshCoordinator checks
/// isActive() and skips accounts whose login is ongoing.
actor LoginGate {
    static let shared = LoginGate()
    private var inProgress: Set<UUID> = []

    func enter(_ id: UUID) { inProgress.insert(id) }
    func leave(_ id: UUID) { inProgress.remove(id) }
    func isActive(_ id: UUID) -> Bool { inProgress.contains(id) }
}

@MainActor
final class RefreshCoordinator: ObservableObject {
    @Published var states: [UUID: UsageState] = [:]
    @Published var lastRefreshedAt: Date?

    private let store: AccountStore
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(store: AccountStore) {
        self.store = store
        scheduleTimer()
        store.$pollIntervalSeconds
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleTimer() }
            .store(in: &cancellables)
        Task { await refreshAll() }
    }

    func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(60, store.pollIntervalSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }

    func refreshAll() async {
        let accounts = store.accounts
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { @MainActor in await self.refresh(account) }
            }
        }
        lastRefreshedAt = Date()
    }

    func forget(_ id: UUID) {
        states.removeValue(forKey: id)
    }

    func refresh(_ account: Account) async {
        // Skip refreshing accounts with an in-progress login. Otherwise a
        // timer tick that fires between "save OAuth" and "validate token"
        // can read partial state and push an .error that immediately
        // overwrites the .loaded we're about to set.
        if await LoginGate.shared.isActive(account.id) {
            FileHandle.standardError.write(Data(
                "[refresh] skipped \(account.id) — login in progress\n".utf8
            ))
            return
        }

        let previous = states[account.id]
        states[account.id] = .loading
        do {
            let snap = try await api(for: account).fetch(account: account)
            states[account.id] = .loaded(snap)
            UsageNotifier.shared.evaluate(account: account, snapshot: snap)
        } catch {
            // Transient API errors (rate limits, brief network drops) used
            // to immediately blank the popover. If we have a recent good
            // snapshot, keep showing it rather than flashing "Not signed
            // in" — the next successful fetch will replace it.
            if case .loaded(let old) = previous,
               Date().timeIntervalSince(old.fetchedAt) < 60 {
                states[account.id] = .loaded(old)
            } else {
                states[account.id] = .error(error.localizedDescription)
            }
        }
    }

    private func api(for account: Account) -> UsageAPI {
        switch account.provider {
        case .claude: return AnthropicUsageAPI()
        case .codex:  return OpenAIUsageAPI()
        }
    }
}
