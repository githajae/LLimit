import XCTest
@testable import LLimit

final class MenuBarAccountTests: XCTestCase {
    func testMainAccountNarrowsMenuBarAndMissingOneFallsBackToAll() {
        let claude = Account(name: "Claude", provider: .claude, configDir: "/tmp/c")
        let codex = Account(name: "Codex", provider: .codex, configDir: "/tmp/x")
        let accounts = [claude, codex]

        XCTAssertEqual(MenuBarAccount.shown(in: accounts, selection: "").map(\.id), [claude.id, codex.id])
        XCTAssertEqual(MenuBarAccount.shown(in: accounts, selection: codex.id.uuidString).map(\.id), [codex.id])
        XCTAssertNil(MenuBarAccount.main(in: accounts, selection: UUID().uuidString))
        XCTAssertEqual(MenuBarAccount.shown(in: accounts, selection: UUID().uuidString).count, 2)
    }

    func testBarsFollowPopoverOrder() throws {
        func snapshot(_ windows: [(String, Double)]) -> UsageSnapshot {
            UsageSnapshot(fetchedAt: Date(), windows: windows.map { UsageWindow(label: $0.0, usedPercent: $0.1) })
        }
        let claude = snapshot([("7d", 0.69), ("Weekly · Fable", 0.27)])
        let codex = snapshot([("5h", 0.10), ("7d", 0.04)])

        let main = MenuBarAccount.bars(for: [claude])
        XCTAssertEqual(try XCTUnwrap(main.top), 0.69, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(main.bottom), 0.27, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(main.mostUsed), 0.69, accuracy: 1e-9)

        let all = MenuBarAccount.bars(for: [claude, codex, snapshot([("7d", 0.21)])])
        XCTAssertEqual(try XCTUnwrap(all.top), 0.69, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(all.bottom), 0.27, accuracy: 1e-9)

        let single = MenuBarAccount.bars(for: [snapshot([("7d", 0.21)])])
        XCTAssertNil(single.bottom)
    }

    func testOnlyMainAccountWarns() {
        let main = Account(name: "Claude", provider: .claude, configDir: "/tmp/c")
        let other = Account(name: "Work", provider: .claude, configDir: "/tmp/w")
        let accounts = [main, other]

        XCTAssertTrue(UsageNotifier.warns(for: main, accounts: accounts, selection: main.id.uuidString))
        XCTAssertFalse(UsageNotifier.warns(for: other, accounts: accounts, selection: main.id.uuidString))
        XCTAssertTrue(UsageNotifier.warns(for: other, accounts: accounts, selection: ""))
        XCTAssertTrue(UsageNotifier.warns(for: other, accounts: accounts, selection: UUID().uuidString))
    }
}
