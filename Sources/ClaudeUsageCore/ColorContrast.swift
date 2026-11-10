// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// WCAG contrast between `#RRGGBB` colours, and the nearest shade of a colour
/// that stands out from a background.
///
/// A colour the user picks for the owl's eyes also colours the menu's bars
/// and percentages, and nothing says it reads on a menu: a pale yellow
/// vanishes on a light one, a navy on a dark one. `readable` keeps the hue
/// and moves only the lightness, and only as far as it has to.
public enum ColorContrast {
    /// A light menu's background and a dark one's, near enough: a menu is
    /// translucent, so its real colour drifts with what is behind it.
    public static let lightMenuHex = "#FFFFFF"
    public static let darkMenuHex = "#2A2A2A"

    /// The WCAG contrast ratio of two colours, 1 (the same) to 21 (black on
    /// white). Nil-safe: an unreadable hex counts as black.
    public static func ratio(_ a: String, _ b: String) -> Double {
        let (la, lb) = (luminance(rgb(a)), luminance(rgb(b)))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `hex` itself if it is at least `minimum`:1 against `background`, else
    /// the same hue and saturation at the nearest lightness that is: lighter
    /// on a dark background, darker on a light one.
    public static func readable(_ hex: String, on background: String, minimum: Double = 4.5) -> String {
        guard ratio(hex, background) < minimum else { return normalized(hex) }
        let (h, s, l) = hsl(rgb(hex))
        let lighten = luminance(rgb(background)) < 0.18
        // Contrast only grows as the lightness moves away from the
        // background's, so bisect between where it is and the far end.
        var (near, far) = (l, lighten ? 1.0 : 0.0)
        for _ in 0..<24 {
            let mid = (near + far) / 2
            if ratio(string(fromHSL: (h, s, mid)), background) < minimum { near = mid } else { far = mid }
        }
        return string(fromHSL: (h, s, far))
    }

    /// `hex` as `#RRGGBB` in capitals, or nil if it is not a colour.
    public static func parse(_ hex: String) -> String? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, UInt32(text, radix: 16) != nil else { return nil }
        return "#" + text.uppercased()
    }

    // MARK: - Internals

    private typealias RGB = (r: Double, g: Double, b: Double)

    private static func normalized(_ hex: String) -> String { parse(hex) ?? "#000000" }

    private static func rgb(_ hex: String) -> RGB {
        let value = UInt32(normalized(hex).dropFirst(), radix: 16) ?? 0
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    private static func luminance(_ c: RGB) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private static func hsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
        let (hi, lo) = (max(c.r, c.g, c.b), min(c.r, c.g, c.b))
        let l = (hi + lo) / 2, d = hi - lo
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if hi == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) } else if hi == c.g { h = (c.b - c.r) / d + 2 } else { h = (c.r - c.g) / d + 4 }
        h /= 6
        return (h < 0 ? h + 1 : h, min(1, s), l)
    }

    private static func string(fromHSL c: (h: Double, s: Double, l: Double)) -> String {
        let chroma = (1 - abs(2 * c.l - 1)) * c.s
        let h6 = c.h * 6
        let x = chroma * (1 - abs(h6.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): RGB
        switch Int(h6) % 6 {
        case 0: (r, g, b) = (chroma, x, 0)
        case 1: (r, g, b) = (x, chroma, 0)
        case 2: (r, g, b) = (0, chroma, x)
        case 3: (r, g, b) = (0, x, chroma)
        case 4: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        let m = c.l - chroma / 2
        func byte(_ v: Double) -> Int { max(0, min(255, Int(((v + m) * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
