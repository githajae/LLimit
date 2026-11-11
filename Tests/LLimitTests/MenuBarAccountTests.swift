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
}
