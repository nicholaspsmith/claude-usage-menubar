// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// One colour for the session window and another for the weekly, chosen
/// together from a short list of pairs, in place of the green-to-red usage
/// ramp.
///
/// Pairs rather than two free pickers: the list is short, every pair is
/// guaranteed to differ, and nobody has to hunt for two hues that read well
/// side by side. Colours are hex strings so the choice is readable in
/// `defaults read` and the core stays free of AppKit.
public struct ColorPair: Equatable, Sendable {
    public let id: String
    public let name: String
    public let sessionHex: String
    public let weeklyHex: String
    /// The same two hues in light shades, for the menu's bars and text on a
    /// dark menu, where the deep ones (made for the owl's eye white) sink in.
    public let sessionOnDarkHex: String
    public let weeklyOnDarkHex: String

    /// A new key rather than the old `ColorPair` one: that choice has been
    /// ignored since colour started carrying data, and quietly reviving a pair
    /// picked a month ago would look like a bug.
    public static let key = "WindowColors"

    /// Every colour is deep enough to read as a pupil on the owl's eye white:
    /// at least 4.5:1 on white and 3:1 on the pink of a spent week (#FFB3B3).
    /// Each on-dark shade is at least 4.5:1 on a dark menu (#2A2A2A).
    public static let presets: [ColorPair] = [
        ColorPair(id: "grape-mint",     name: "Grape & Mint",     sessionHex: "#7A3EE2", weeklyHex: "#09744B",
                  sessionOnDarkHex: "#B18EEE", weeklyOnDarkHex: "#5FD3A6"),
        ColorPair(id: "sky-tangerine",  name: "Sky & Tangerine",  sessionHex: "#0B65BB", weeklyHex: "#A04E00",
                  sessionOnDarkHex: "#5AA9F5", weeklyOnDarkHex: "#FF9F43"),
        ColorPair(id: "lime-fuchsia",   name: "Lime & Fuchsia",   sessionHex: "#3B7209", weeklyHex: "#B91A8E",
                  sessionOnDarkHex: "#8CD64A", weeklyOnDarkHex: "#E85BC2"),
        ColorPair(id: "rose-cobalt",    name: "Rose & Cobalt",    sessionHex: "#C7143F", weeklyHex: "#2A52F3",
                  sessionOnDarkHex: "#F06A8A", weeklyOnDarkHex: "#6C8AFF"),
    ]

    /// The chosen pair, or nil for the usage ramp (the default, and the
    /// answer for an id this build doesn't know).
    public static func stored(in defaults: UserDefaults = .standard) -> ColorPair? {
        guard let id = defaults.string(forKey: key) else { return nil }
        return presets.first(where: { $0.id == id })
    }

    /// Saves `pair`, or the usage ramp for nil.
    public static func save(_ pair: ColorPair?, to defaults: UserDefaults = .standard) {
        if let pair { defaults.set(pair.id, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
