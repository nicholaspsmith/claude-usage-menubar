import Foundation

/// One colour for the session window and another for the weekly, chosen
/// together from a short list of pairs.
///
/// The two windows share the menu and the owl's face, so each needs a colour
/// of its own to be told apart. Pairs rather than two free pickers: the list is
/// short, every pair is guaranteed to differ, and nobody has to hunt for two
/// hues that read well side by side. Colours are hex strings so the choice is
/// readable in `defaults read` and the core stays free of AppKit.
public struct ColorPair: Equatable, Sendable {
    public let id: String
    public let name: String
    public let sessionHex: String
    public let weeklyHex: String

    public static let key = "ColorPair"

    public static let presets: [ColorPair] = [
        ColorPair(id: "grape-mint",     name: "Grape & Mint",     sessionHex: "#B18EEE", weeklyHex: "#5FD3A6"),
        ColorPair(id: "sky-tangerine",  name: "Sky & Tangerine",  sessionHex: "#5AA9F5", weeklyHex: "#FF9F43"),
        ColorPair(id: "lime-fuchsia",   name: "Lime & Fuchsia",   sessionHex: "#8CD64A", weeklyHex: "#E85BC2"),
        ColorPair(id: "rose-cobalt",    name: "Rose & Cobalt",    sessionHex: "#F06A8A", weeklyHex: "#4C6EF5"),
    ]

    /// Grape & Mint: its session purple is what the app drew before the weekly
    /// window had a colour at all, so an upgrade changes nothing already seen.
    public static let `default` = presets[0]

    public static func stored(in defaults: UserDefaults = .standard) -> ColorPair {
        guard let id = defaults.string(forKey: key),
              let match = presets.first(where: { $0.id == id }) else { return .default }
        return match
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: Self.key)
    }
}
