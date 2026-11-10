// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ClaudeUsageCore

final class ColorPairTests: XCTestCase {
    private func defaults() -> UserDefaults {
        scratchDefaults("ColorPairTests")
    }

    // The whole point of a pair is that the two windows can be told apart.
    func testEveryPairHasTwoDifferentColours() {
        XCTAssertEqual(ColorPair.presets.count, 4)
        for pair in ColorPair.presets {
            XCTAssertNotEqual(pair.sessionHex.uppercased(), pair.weeklyHex.uppercased(), pair.name)
        }
        XCTAssertEqual(Set(ColorPair.presets.map(\.id)).count, ColorPair.presets.count)
    }

    // A pupil has to stand out from the owl's eye white: 4.5:1 on white and
    // 3:1 on the pink of a spent week (#FFB3B3).
    func testEveryColourContrastsWithTheEyeWhite() {
        for pair in ColorPair.presets {
            for hex in [pair.sessionHex, pair.weeklyHex] {
                XCTAssertGreaterThan(ColorContrast.ratio(hex, "#FFFFFF"), 4.5, "\(pair.name) \(hex) on white")
                XCTAssertGreaterThan(ColorContrast.ratio(hex, "#FFB3B3"), 3, "\(pair.name) \(hex) on pink")
            }
            // And the menu's bars and text have to stand out from a dark menu.
            for hex in [pair.sessionOnDarkHex, pair.weeklyOnDarkHex] {
                XCTAssertGreaterThan(ColorContrast.ratio(hex, ColorContrast.darkMenuHex), 4.5, "\(pair.name) \(hex) on a dark menu")
            }
        }
    }

    // MARK: - Custom colours

    // Choosing Custom before touching a picker still gives two colours.
    func testCustomStartsOnTwoDifferentColours() {
        let d = defaults()
        d.set(ColorPair.customID, forKey: ColorPair.key)
        let pair = ColorPair.stored(in: d)
        XCTAssertEqual(pair?.isCustom, true)
        XCTAssertEqual(pair?.sessionHex, ColorPair.customDefaults.left)
        XCTAssertEqual(pair?.weeklyHex, ColorPair.customDefaults.right)
        XCTAssertFalse(ColorPair.presets.contains(where: \.isCustom))
    }

    // Each eye keeps the colour picked for it: left first, right second.
    func testCustomColoursRoundTripPerEye() {
        let d = defaults()
        ColorPair.setCustomColor("#ff0000", left: true, in: d)
        ColorPair.setCustomColor("0000FF", left: false, in: d)
        let pair = ColorPair.custom(in: d)
        XCTAssertEqual(pair.sessionHex, "#FF0000")
        XCTAssertEqual(pair.weeklyHex, "#0000FF")
    }

    // "Same colour" gives both eyes the left's, and the right's own colour is
    // still there when it is switched back off.
    func testSameColourFollowsTheLeftEyeAndForgetsNothing() {
        let d = defaults()
        ColorPair.setCustomColor("#FF0000", left: true, in: d)
        ColorPair.setCustomColor("#0000FF", left: false, in: d)
        XCTAssertFalse(ColorPair.customSame(in: d))
        ColorPair.setCustomSame(true, in: d)
        XCTAssertEqual(ColorPair.custom(in: d).sessionHex, "#FF0000")
        XCTAssertEqual(ColorPair.custom(in: d).weeklyHex, "#FF0000")
        ColorPair.setCustomSame(false, in: d)
        XCTAssertEqual(ColorPair.custom(in: d).weeklyHex, "#0000FF")
    }

    // A hand-edited default that is not a colour must not break the icon.
    func testNonsenseCustomColourIsIgnored() {
        let d = defaults()
        ColorPair.setCustomColor("chartreuse", left: true, in: d)
        XCTAssertEqual(ColorPair.custom(in: d).sessionHex, ColorPair.customDefaults.left)
        d.set("#12", forKey: ColorPair.customRightKey)
        XCTAssertEqual(ColorPair.custom(in: d).weeklyHex, ColorPair.customDefaults.right)
    }

    // Whatever is picked, the menu's bars stay readable on a dark menu.
    func testCustomColoursGetAReadableShadeForADarkMenu() {
        let d = defaults()
        ColorPair.setCustomColor("#000080", left: true, in: d)   // navy: sinks into a dark menu
        ColorPair.setCustomColor("#FFE066", left: false, in: d)  // pale yellow: already fine there
        let pair = ColorPair.custom(in: d)
        XCTAssertEqual(pair.sessionHex, "#000080", "the pupil wears it as picked")
        XCTAssertGreaterThanOrEqual(ColorContrast.ratio(pair.sessionOnDarkHex, ColorContrast.darkMenuHex), 4.5)
        XCTAssertEqual(pair.weeklyOnDarkHex, "#FFE066")
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
