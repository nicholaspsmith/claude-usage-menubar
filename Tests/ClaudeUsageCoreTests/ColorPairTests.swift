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
        func luminance(_ hex: String) -> Double {
            let value = UInt32(hex.dropFirst(), radix: 16)!
            func lin(_ shift: UInt32) -> Double {
                let v = Double((value >> shift) & 0xFF) / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(16) + 0.7152 * lin(8) + 0.0722 * lin(0)
        }
        for pair in ColorPair.presets {
            for hex in [pair.sessionHex, pair.weeklyHex] {
                XCTAssertGreaterThan((luminance("#FFFFFF") + 0.05) / (luminance(hex) + 0.05), 4.5, "\(pair.name) \(hex) on white")
                XCTAssertGreaterThan((luminance("#FFB3B3") + 0.05) / (luminance(hex) + 0.05), 3, "\(pair.name) \(hex) on pink")
            }
            // And the menu's bars and text have to stand out from a dark menu.
            for hex in [pair.sessionOnDarkHex, pair.weeklyOnDarkHex] {
                XCTAssertGreaterThan((luminance(hex) + 0.05) / (luminance("#2A2A2A") + 0.05), 4.5, "\(pair.name) \(hex) on a dark menu")
            }
        }
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
