// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ClaudeUsageCore

final class GoOutsideTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 3600
    func weekly(_ fraction: Double, left: TimeInterval?) -> UsageLimit {
        UsageLimit(label: UsageLimit.weeklyLabel, fraction: fraction, resetsAt: left.map { now.addingTimeInterval($0) })
    }
    var defaults: UserDefaults!
    override func setUp() { defaults = UserDefaults(suiteName: "GoOutsideTests-\(UUID().uuidString)")! }

    // MARK: When it is due

    func testASpentWeekWithMoreThanADayLeftIsDue() {
        XCTAssertTrue(GoOutside.isDue(weekly(1, left: 25 * hour), now: now))
    }

    func testADayOrLessLeftIsNot() {
        XCTAssertFalse(GoOutside.isDue(weekly(1, left: 24 * hour), now: now))
        XCTAssertFalse(GoOutside.isDue(weekly(1, left: 3 * hour), now: now))
    }

    func testAWeekNotYetSpentIsNot() {
        XCTAssertFalse(GoOutside.isDue(weekly(0.99, left: 72 * hour), now: now))
    }

    func testNoResetTimeOrNoWeeklyWindowIsNot() {
        XCTAssertFalse(GoOutside.isDue(weekly(1, left: nil), now: now))
        XCTAssertFalse(GoOutside.isDue(nil, now: now))
    }

    func testTheWeeklyWindowIsFoundByLabelNotPlace() {
        // With no five-hour window in the payload the weekly one comes first.
        let w = weekly(1, left: 30 * hour)
        XCTAssertEqual(GoOutside.weekly(in: [w])?.label, UsageLimit.weeklyLabel)
        let session = UsageLimit(label: UsageLimit.sessionLabel, fraction: 1, resetsAt: now)
        XCTAssertNil(GoOutside.weekly(in: [session]))
    }

    // MARK: How it looks

    func testItFadesInOverTwoSecondsHoldsFiveAndFadesOutInOne() {
        XCTAssertEqual(GoOutside.duration, 8)
        XCTAssertEqual(GoOutside.frame(at: 0, reduceMotion: false)!.alpha, 0, accuracy: 1e-9)
        let shown = GoOutside.frame(at: GoOutside.fadeIn, reduceMotion: false)!
        XCTAssertEqual(shown.alpha, 1, accuracy: 1e-9)
        XCTAssertEqual(shown.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(GoOutside.frame(at: 4.5, reduceMotion: false)!.alpha, 1, accuracy: 1e-9)
        let leaving = GoOutside.frame(at: 7.5, reduceMotion: false)!
        XCTAssertGreaterThan(leaving.alpha, 0)
        XCTAssertLessThan(leaving.alpha, 1)
        XCTAssertNil(GoOutside.frame(at: GoOutside.duration, reduceMotion: false))
    }

    func testTheFadeInBounces() {
        // Not a plain grow: somewhere in the fade-in the bubble shrinks back a little.
        let scales = stride(from: 0.0, through: GoOutside.fadeIn, by: 0.02).map { GoOutside.frame(at: $0, reduceMotion: false)!.scale }
        XCTAssertTrue(zip(scales, scales.dropFirst()).contains { $1 < $0 - 0.001 })
        XCTAssertGreaterThan(scales.min()!, 0)
    }

    func testReduceMotionKeepsTheFadeAndDropsTheBounce() {
        for t in stride(from: 0.0, to: GoOutside.duration, by: 0.1) {
            XCTAssertEqual(GoOutside.frame(at: t, reduceMotion: true)!.scale, 1, accuracy: 1e-9)
        }
        XCTAssertEqual(GoOutside.frame(at: 1, reduceMotion: true)!.alpha, 0.5, accuracy: 0.01)
    }

    // MARK: After the click

    func testAClickShutsHisEyesUntilTheWeekResets() {
        let w = weekly(1, left: 72 * hour)
        XCTAssertFalse(GoOutside.eyesShut(now: now, in: defaults))
        GoOutside.dismiss(w, in: defaults)
        XCTAssertTrue(GoOutside.eyesShut(now: now, in: defaults))
        XCTAssertTrue(GoOutside.eyesShut(now: now.addingTimeInterval(71 * hour), in: defaults))
        XCTAssertFalse(GoOutside.eyesShut(now: now.addingTimeInterval(72 * hour), in: defaults))
    }

    func testTheBubbleIsNotDueWhileHisEyesAreShut() {
        let w = weekly(1, left: 72 * hour)
        GoOutside.dismiss(w, in: defaults)
        XCTAssertFalse(GoOutside.shouldShow(w, now: now, in: defaults))
        XCTAssertTrue(GoOutside.shouldShow(w, now: now, in: UserDefaults(suiteName: "GoOutsideTests-\(UUID().uuidString)")!))
    }

    func testTheNextSpentWeekAsksAgain() {
        GoOutside.dismiss(weekly(1, left: 72 * hour), in: defaults)
        let later = now.addingTimeInterval(8 * 24 * hour)
        let nextWeek = UsageLimit(label: UsageLimit.weeklyLabel, fraction: 1, resetsAt: later.addingTimeInterval(48 * hour))
        XCTAssertTrue(GoOutside.shouldShow(nextWeek, now: later, in: defaults))
    }
}
