// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ClaudeUsageCore

final class ColorPairTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ColorPairTests-\(UUID().uuidString)")!
    }

    // The whole point of a pair is that the two windows can be told apart.
    func testEveryPairHasTwoDifferentColours() {
        XCTAssertEqual(ColorPair.presets.count, 4)
        for pair in ColorPair.presets {
            XCTAssertNotEqual(pair.sessionHex.uppercased(), pair.weeklyHex.uppercased(), pair.name)
        }
        XCTAssertEqual(Set(ColorPair.presets.map(\.id)).count, ColorPair.presets.count)
    }

    // A fresh install keeps the usage ramp.
    func testDefaultIsTheUsageRamp() {
        XCTAssertNil(ColorPair.stored(in: defaults()))
    }

    // The pair chosen before colour carried data stays ignored.
    func testOldKeyIsIgnored() {
        let d = defaults()
        d.set("lime-fuchsia", forKey: "ColorPair")
        XCTAssertNil(ColorPair.stored(in: d))
    }

    func testChoiceRoundTripsAndClears() {
        let d = defaults()
        let chosen = ColorPair.presets[2]
        ColorPair.save(chosen, to: d)
        XCTAssertEqual(ColorPair.stored(in: d), chosen)
        ColorPair.save(nil, to: d)
        XCTAssertNil(ColorPair.stored(in: d))
    }

    // A preference outlives the build that wrote it.
    func testUnknownIdFallsBackToTheRamp() {
        let d = defaults()
        d.set("sepia-and-ochre", forKey: ColorPair.key)
        XCTAssertNil(ColorPair.stored(in: d))
    }
}
