import Foundation

/// What the menu shows beyond the limits, chosen by the user and persisted.
public enum MenuPreferences {
    public static let showSessionsKey = "ShowSessions"

    /// Whether the running-sessions section is listed. Off by default: most
    /// of the time the menu is opened for the two bars, and a list of every
    /// agent in every terminal is noise until you want it.
    public static func showSessions(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: showSessionsKey)
    }

    public static func setShowSessions(_ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: showSessionsKey)
    }
}
