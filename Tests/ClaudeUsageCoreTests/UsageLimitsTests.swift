import XCTest
@testable import ClaudeUsageCore

final class UsageLimitsTests: XCTestCase {

    // The scale is decided per payload, not per value. 37.0 alongside any
    // other >= 1 value means 37%, not 3700%.
    func testPercentScalePayload() {
        let limits = UsageLimits.parse(payload: [
            "five_hour": ["utilization": 37.0],
            "seven_day_oauth_apps": ["utilization": 12.5],
        ])
        XCTAssertEqual(limits.count, 2)
        XCTAssertEqual(limits[0].fraction, 0.37, accuracy: 0.0001)
        XCTAssertEqual(limits[1].fraction, 0.125, accuracy: 0.0001)
    }

    // Older fraction-scaled payloads: every value below 1, so 0.37 is 37%.
    func testFractionScalePayload() {
        let limits = UsageLimits.parse(payload: ["five_hour": ["utilization": 0.37]])
        XCTAssertEqual(limits[0].fraction, 0.37, accuracy: 0.0001)
    }

    // The ambiguous case that motivates payload-wide scale detection: a lone
    // 1.0 is one percent when anything else in the payload is percent-scaled.
    func testLoneOneIsPercentWhenPayloadIsPercentScaled() {
        let limits = UsageLimits.parse(payload: [
            "five_hour": ["utilization": 1.0],
            "seven_day_oauth_apps": ["utilization": 40.0],
        ])
        XCTAssertEqual(limits[0].fraction, 0.01, accuracy: 0.0001)
    }

    // 1.0 is its own percent-scale evidence: it is >= 1, so the payload reads
    // as percent-scaled and the value means 1%, not 100%. This is the safe way
    // round — mistaking 1% for a full allowance would cry wolf constantly,
    // while the reverse merely under-reports a nearly-empty window.
    func testLoneOneReadsAsOnePercent() {
        let limits = UsageLimits.parse(payload: ["five_hour": ["utilization": 1.0]])
        XCTAssertEqual(limits[0].fraction, 0.01, accuracy: 0.0001)
    }

    // Just under the threshold, the fraction reading still applies.
    func testJustUnderOneIsFraction() {
        let limits = UsageLimits.parse(payload: ["five_hour": ["utilization": 0.99]])
        XCTAssertEqual(limits[0].fraction, 0.99, accuracy: 0.0001)
    }

    // A scoped `limits` entry can be the only percent-scaled evidence present.
    func testScopedEntriesSettleTheScale() {
        let limits = UsageLimits.parse(payload: [
            "five_hour": ["utilization": 0.5],
            "limits": [["percent": 42.0]],
        ])
        XCTAssertEqual(limits[0].fraction, 0.005, accuracy: 0.0001)
    }

    func testSevenDayFallbackKeyIsUsed() {
        let limits = UsageLimits.parse(payload: ["seven_day": ["utilization": 20.0]])
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits[0].label, "Weekly (7-day)")
    }

    func testOauthAppsKeyWinsOverSevenDay() {
        let limits = UsageLimits.parse(payload: [
            "seven_day_oauth_apps": ["utilization": 20.0],
            "seven_day": ["utilization": 99.0],
        ])
        XCTAssertEqual(limits[0].fraction, 0.20, accuracy: 0.0001)
    }

    // A missing window is absent, never 0% — showing "0% used" for a window
    // the server did not report would read as plenty of headroom.
    func testMissingBucketIsOmitted() {
        XCTAssertTrue(UsageLimits.parse(payload: [:]).isEmpty)
        XCTAssertTrue(UsageLimits.parse(payload: ["five_hour": ["utilization": "n/a"]]).isEmpty)
    }

    func testUtilizationClampsAtFull() {
        let limits = UsageLimits.parse(payload: ["five_hour": ["utilization": 140.0]])
        XCTAssertEqual(limits[0].fraction, 1.0, accuracy: 0.0001)
    }

    func testStringUtilizationWithPercentSign() {
        let limits = UsageLimits.parse(payload: ["five_hour": ["utilization": "37%"]])
        XCTAssertEqual(limits[0].fraction, 0.37, accuracy: 0.0001)
    }

    // MARK: - resets_at

    func testResetAcceptsISO8601() throws {
        let date = try XCTUnwrap(UsageLimits.resetDate("2026-08-25T18:00:00Z"))
        XCTAssertEqual(date.timeIntervalSince1970, 1787680800 as Double, accuracy: 1)
    }

    func testResetAcceptsEpochSecondsAndMilliseconds() throws {
        let seconds = try XCTUnwrap(UsageLimits.resetDate(1787680800))
        let millis = try XCTUnwrap(UsageLimits.resetDate(1787680800000))
        XCTAssertEqual(seconds.timeIntervalSince1970, 1787680800 as Double, accuracy: 1)
        XCTAssertEqual(millis.timeIntervalSince1970, 1787680800 as Double, accuracy: 1)
    }

    func testResetRejectsGarbage() {
        XCTAssertNil(UsageLimits.resetDate("soon"))
        XCTAssertNil(UsageLimits.resetDate(nil))
    }

    // A cached limit whose window has since reset describes a refilled
    // allowance and must not be shown as current.
    func testWindowOpenOnlyUntilReset() {
        let past = UsageLimit(label: "x", fraction: 0.5, resetsAt: Date(timeIntervalSince1970: 1))
        let future = UsageLimit(label: "x", fraction: 0.5, resetsAt: Date.distantFuture)
        XCTAssertFalse(past.isOpen())
        XCTAssertTrue(future.isOpen())
        XCTAssertTrue(UsageLimit(label: "x", fraction: 0.5, resetsAt: nil).isOpen())
    }
}


final class LimitRowTests: XCTestCase {
    private func limit(_ fraction: Double, resetsIn seconds: TimeInterval?) -> UsageLimit {
        UsageLimit(label: "x", fraction: fraction,
                   resetsAt: seconds.map { Date(timeIntervalSince1970: 1_000_000 + $0) })
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testPercentRounds() {
        XCTAssertEqual(LimitRow.percentText(limit(0.374, resetsIn: nil)), "37%")
        XCTAssertEqual(LimitRow.percentText(limit(1.0, resetsIn: nil)), "100%")
    }

    func testResetFormatsHoursMinutesAndDays() {
        XCTAssertEqual(LimitRow.resetText(limit(0.5, resetsIn: 8_040), now: now), "resets in 2h 14m")
        XCTAssertEqual(LimitRow.resetText(limit(0.5, resetsIn: 900), now: now), "resets in 15m")
        XCTAssertEqual(LimitRow.resetText(limit(0.5, resetsIn: 200_000), now: now), "resets in 2d 7h")
    }

    // A window already past its reset counts nothing — it has refilled.
    func testElapsedWindowSaysNothing() {
        XCTAssertEqual(LimitRow.resetText(limit(0.5, resetsIn: -60), now: now), "")
        XCTAssertEqual(LimitRow.resetText(limit(0.5, resetsIn: nil), now: now), "")
    }
}
