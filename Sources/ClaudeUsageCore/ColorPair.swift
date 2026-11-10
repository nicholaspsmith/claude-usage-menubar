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
/// The list of pairs is short, every one is guaranteed to differ, and nobody
/// has to hunt for two hues that read well side by side. For anyone who would
/// rather hunt, the last choice is `custom`: two colours of the user's own,
/// or one for both. Colours are hex strings so the choice is readable in
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
    ]

    /// The chosen pair, or nil for the usage ramp (the default, and the
    /// answer for an id this build doesn't know).
    public static func stored(in defaults: UserDefaults = .standard) -> ColorPair? {
        guard let id = defaults.string(forKey: key) else { return nil }
        if id == customID { return custom(in: defaults) }
        return presets.first(where: { $0.id == id })
    }

    // MARK: - Custom colours

    /// The id of the user's own colours. Unlike a preset, whose pupils both
    /// take the weekly colour unless each eye has its own window, a custom
    /// pair always gives the left eye its first colour and the right its
    /// second: the user chose them for the eyes.
    public static let customID = "custom"
    public static let customLeftKey = "CustomLeftEyeColor"
    public static let customRightKey = "CustomRightEyeColor"
    public static let customSameKey = "CustomEyeColorsSame"
    /// What the pickers start on: Grape & Mint's pupils.
    public static let customDefaults = (left: "#7A3EE2", right: "#09744B")

    public var isCustom: Bool { id == Self.customID }

    /// The left eye's stored colour and the right's, as picked: the right
    /// keeps its own even while "same colour" has it follow the left.
    public static func customColors(in defaults: UserDefaults = .standard) -> (left: String, right: String) {
        (defaults.string(forKey: customLeftKey).flatMap(ColorContrast.parse) ?? customDefaults.left,
         defaults.string(forKey: customRightKey).flatMap(ColorContrast.parse) ?? customDefaults.right)
    }

    /// Whether both eyes share the left eye's colour. Off by default.
    public static func customSame(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: customSameKey)
    }

    public static func setCustomSame(_ same: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(same, forKey: customSameKey)
    }

    /// Saves one eye's colour; anything that is not `#RRGGBB` is ignored.
    public static func setCustomColor(_ hex: String, left: Bool, in defaults: UserDefaults = .standard) {
        guard let hex = ColorContrast.parse(hex) else { return }
        defaults.set(hex, forKey: left ? customLeftKey : customRightKey)
    }

    /// The user's own colours as a pair: left eye and session bar first,
    /// right eye and weekly bar second, or the left's for both when they are
    /// set to match. The pupils wear the colours exactly as picked; the menu
    /// on a dark background gets the nearest shade of each that reads there.
    public static func custom(in defaults: UserDefaults = .standard) -> ColorPair {
        let picked = customColors(in: defaults)
        let right = customSame(in: defaults) ? picked.left : picked.right
        return ColorPair(id: customID, name: "Custom", sessionHex: picked.left, weeklyHex: right,
                         sessionOnDarkHex: ColorContrast.readable(picked.left, on: ColorContrast.darkMenuHex),
                         weeklyOnDarkHex: ColorContrast.readable(right, on: ColorContrast.darkMenuHex))
    }

    /// Saves `pair`, or the usage ramp for nil.
    public static func save(_ pair: ColorPair?, to defaults: UserDefaults = .standard) {
        if let pair { defaults.set(pair.id, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
