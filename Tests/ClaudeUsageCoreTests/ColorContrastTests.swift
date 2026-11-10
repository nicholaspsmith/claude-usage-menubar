// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ClaudeUsageCore

final class ColorContrastTests: XCTestCase {
    func testRatioRunsFromOneToTwentyOne() {
        XCTAssertEqual(ColorContrast.ratio("#000000", "#FFFFFF"), 21, accuracy: 0.01)
        XCTAssertEqual(ColorContrast.ratio("#FFFFFF", "#000000"), 21, accuracy: 0.01)
        XCTAssertEqual(ColorContrast.ratio("#7A3EE2", "#7A3EE2"), 1, accuracy: 0.001)
        XCTAssertEqual(ColorContrast.ratio("#767676", "#FFFFFF"), 4.54, accuracy: 0.01)
    }

    // A colour that already reads is left exactly as picked.
    func testReadableLeavesAGoodColourAlone() {
        XCTAssertEqual(ColorContrast.readable("#5fd3a6", on: ColorContrast.darkMenuHex), "#5FD3A6")
        XCTAssertEqual(ColorContrast.readable("#7A3EE2", on: ColorContrast.lightMenuHex), "#7A3EE2")
    }

    // One that doesn't is moved just far enough, lighter on dark and darker
    // on light, for every hue and for greys, black and white.
    func testReadableReachesTheMinimumOnBothMenus() {
        let picks = ["#000000", "#FFFFFF", "#808080", "#000080", "#FFFF00", "#FF0000", "#00FF00",
                     "#0000FF", "#FF00FF", "#00FFFF", "#5C4033", "#FFE4E1", "#123456", "#FEDCBA"]
        for hex in picks {
            for menu in [ColorContrast.lightMenuHex, ColorContrast.darkMenuHex] {
                let shade = ColorContrast.readable(hex, on: menu)
                XCTAssertGreaterThanOrEqual(ColorContrast.ratio(shade, menu), 4.5, "\(hex) on \(menu) gave \(shade)")
                XCTAssertLessThan(ColorContrast.ratio(shade, menu), ColorContrast.ratio(hex, menu) < 4.5 ? 5 : 22,
                                  "\(hex) on \(menu) moved further than it had to: \(shade)")
            }
        }
    }

    // Only the lightness moves: a navy stays blue on a dark menu.
    func testReadableKeepsTheHue() {
        let shade = ColorContrast.readable("#000080", on: ColorContrast.darkMenuHex)
        let value = UInt32(shade.dropFirst(), radix: 16)!
        let (r, g, b) = ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        XCTAssertEqual(r, g); XCTAssertGreaterThan(b, r)
    }

    func testParseAcceptsHexWithOrWithoutTheHash() {
        XCTAssertEqual(ColorContrast.parse("#a1b2c3"), "#A1B2C3")
        XCTAssertEqual(ColorContrast.parse(" A1B2C3 "), "#A1B2C3")
        XCTAssertNil(ColorContrast.parse("#A1B2"))
        XCTAssertNil(ColorContrast.parse("purple"))
    }
}
