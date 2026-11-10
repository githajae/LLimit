import XCTest
@testable import LLimit

final class GrokUsageTests: XCTestCase {
    func testBillingResponseBecomesWeeklyWindowWithProductNote() throws {
        let json = #"""
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-11-09T11:52:05.732303+00:00","end":"2026-11-16T11:52:05.732303+00:00"},
         "creditUsagePercent":13.0,"onDemandCap":{"val":0},"onDemandUsed":{"val":0},
         "productUsage":[{"product":"GrokBuild","usagePercent":11.0},{"product":"GrokChat","usagePercent":2.0}],
         "isUnifiedBillingUser":true,"prepaidBalance":{"val":0},
         "billingPeriodStart":"2026-11-09T11:52:05.732303+00:00","billingPeriodEnd":"2026-11-16T11:52:05.732303+00:00"}}
        """#
        let billing = try JSONDecoder().decode(GrokUsageAPI.BillingResponse.self, from: Data(json.utf8))
        let snapshot = billing.snapshot(email: "user@example.com")
        XCTAssertEqual(snapshot.windows.map(\.label), ["7d"])
        XCTAssertEqual(try XCTUnwrap(snapshot.windows.first?.usedPercent), 0.13, accuracy: 1e-9)
        XCTAssertNotNil(snapshot.windows.first?.resetsAt)
        XCTAssertEqual(snapshot.note, "Build 11% · Chat 2%")
        XCTAssertEqual(snapshot.email, "user@example.com")
    }

    func testMissingUsageKeepsEmptyWindows() throws {
        let billing = try JSONDecoder().decode(GrokUsageAPI.BillingResponse.self, from: Data(#"{"config":{}}"#.utf8))
        XCTAssertTrue(billing.snapshot(email: nil).windows.isEmpty)
        XCTAssertNil(billing.productNote)
    }

    func testAuthPicksLongestLivedToken() throws {
        let json = #"""
        {"https://auth.x.ai::a":{"key":"old","email":"a@example.com","expires_at":"2026-11-10T01:00:00.000001Z"},
         "https://auth.x.ai::b":{"key":"new","email":"b@example.com","expires_at":"2026-11-10T10:41:28.900721Z"},
         "https://auth.x.ai::c":{"key":"","expires_at":"2027-01-01T00:00:00Z"}}
        """#
        let auth = try GrokUsageAPI.parseAuth(Data(json.utf8))
        XCTAssertEqual(auth.token, "new")
        XCTAssertEqual(auth.email, "b@example.com")
        XCTAssertNotNil(auth.expiresAt)
    }

    func testAuthWithoutTokenIsSignedOut() {
        XCTAssertThrowsError(try GrokUsageAPI.parseAuth(Data("{}".utf8)))
        XCTAssertThrowsError(try GrokUsageAPI.parseAuth(Data("not json".utf8)))
    }
}
