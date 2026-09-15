import SwiftUI
import AppKit

@main
struct LLimitApp: App {
    @StateObject private var accountStore: AccountStore
    @StateObject private var refresher: RefreshCoordinator

    init() {
        if let dest = Self.readmeSnapshotPath() {
            ReadmeSnapshot.export(to: dest)
            Foundation.exit(0)
        }
        let store = AccountStore()
        let coord = RefreshCoordinator(store: store)
        _accountStore = StateObject(wrappedValue: store)
        _refresher = StateObject(wrappedValue: coord)
        NSApplication.shared.setActivationPolicy(.accessory)
        UsageNotifier.shared.requestAuthorization()
    }

    private static func readmeSnapshotPath() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--readme-snapshot") else { return nil }
        if let next = args.dropFirst(i + 1).first, !next.hasPrefix("-") {
            return next
        }
        return "Resources/screenshot.png"
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(accountStore)
                .environmentObject(refresher)
        } label: {
            MenuBarLabel()
                .environmentObject(accountStore)
                .environmentObject(refresher)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(accountStore)
                .environmentObject(refresher)
        }
    }
}
