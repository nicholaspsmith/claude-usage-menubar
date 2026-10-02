// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ClaudeUsageCore

final class BlinkTests: XCTestCase {
    func testOpenBeforeAndAfter() {
        XCTAssertEqual(Blink.closure(at: -0.01), 0)
        XCTAssertNil(Blink.closure(at: Blink.duration))
        XCTAssertEqual(Blink.closure(at: 0), 0)
    }

    func testShutThroughTheHold() {
        XCTAssertEqual(Blink.closure(at: Blink.closing)!, 1, accuracy: 1e-9)
        XCTAssertEqual(Blink.closure(at: Blink.closing + Blink.hold / 2)!, 1, accuracy: 1e-9)
        XCTAssertEqual(Blink.closure(at: Blink.closing + Blink.hold)!, 1, accuracy: 1e-9)
    }

    // A real lid falls slowly at first then accelerates, and comes back up
    // fast before a long settling tail — so halfway through the fall the lid
    // is still mostly up, and halfway through the rise it is mostly open.
    func testClosingAcceleratesAndOpeningSettles() {
        XCTAssertLessThan(Blink.closure(at: Blink.closing / 2)!, 0.5)
        let openStart = Blink.closing + Blink.hold
        XCTAssertLessThan(Blink.closure(at: openStart + Blink.opening / 2)!, 0.5)
        XCTAssertGreaterThan(Blink.closure(at: openStart + Blink.opening * 0.9)!, 0)
    }

    func testOpeningIsSlowerThanClosing() {
        XCTAssertGreaterThan(Blink.opening, Blink.closing * 2)
    }

    func testMonotonic() {
        var last: Double = 0
        var t = 0.0
        while t <= Blink.closing + Blink.hold {
            let v = Blink.closure(at: t)!
            XCTAssertGreaterThanOrEqual(v, last - 1e-12); last = v; t += 0.005
        }
        while t < Blink.duration {
            let v = Blink.closure(at: t)!
            XCTAssertLessThanOrEqual(v, last + 1e-12); last = v; t += 0.005
        }
    }

    func testNextMinute() {
        let mid = Date(timeIntervalSince1970: 1_000_000_030.4)
        XCTAssertEqual(Blink.nextMinute(after: mid).timeIntervalSince1970, 1_000_000_080, accuracy: 1e-6)
        // Exactly on the minute (the timer that just fired) means the next one.
        let on = Date(timeIntervalSince1970: 1_000_000_020)
        XCTAssertEqual(Blink.nextMinute(after: on).timeIntervalSince1970, 1_000_000_080, accuracy: 1e-6)
    }
}
