// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Archimedes has a word when the week is spent with more than a day of it
/// left: a speech bubble under the owl, pointing at his beak, once a minute
/// until it is clicked. Then he shuts his eyes, and keeps them shut until the
/// weekly window resets.
public enum GoOutside {
    public static let text = "Dude…go outside!"
    /// Less than a day from the reset, the week is nearly back anyway.
    public static let minimumLeft: TimeInterval = 24 * 3600
    public static let fadeIn: TimeInterval = 2
    public static let hold: TimeInterval = 5
    public static let fadeOut: TimeInterval = 1
    public static var duration: TimeInterval { fadeIn + hold + fadeOut }
    /// The smallest the bubble is drawn while it bounces in: big enough to read as a bubble.
    static let smallest = 0.3
    static let shutUntilKey = "GoOutsideEyesShutUntil"

    /// The weekly window, by its label: with no five-hour window in the
    /// payload it is the first in the list, not the second.
    public static func weekly(in limits: [UsageLimit]) -> UsageLimit? {
        limits.first { $0.label == UsageLimit.weeklyLabel }
    }

    /// The week is spent and more than a day of it is left.
    public static func isDue(_ weekly: UsageLimit?, now: Date) -> Bool {
        guard let weekly, weekly.fraction >= 1, let resetsAt = weekly.resetsAt else { return false }
        return resetsAt.timeIntervalSince(now) > minimumLeft
    }

    /// Due, and not already answered with a click this week.
    public static func shouldShow(_ weekly: UsageLimit?, now: Date, in defaults: UserDefaults = .standard) -> Bool {
        isDue(weekly, now: now) && !eyesShut(now: now, in: defaults)
    }

    /// The bubble `elapsed` seconds into one showing: its opacity, and its
    /// scale about the tail's tip. It fades in over two seconds while it
    /// bounces in and out to full size (Reduce Motion: no bounce), holds five,
    /// fades out over one. `nil` once it is over.
    public static func frame(at elapsed: TimeInterval, reduceMotion: Bool) -> (alpha: Double, scale: Double)? {
        let t = max(0, elapsed)
        if t < fadeIn {
            let p = t / fadeIn
            let alpha = (1 - cos(.pi * p)) / 2
            let scale = reduceMotion ? 1 : smallest + (1 - smallest) * bounceInOut(p)
            return (alpha, scale)
        }
        if t < fadeIn + hold { return (1, 1) }
        if t < duration {
            let p = (t - fadeIn - hold) / fadeOut
            return ((1 + cos(.pi * p)) / 2, 1)
        }
        return nil
    }

    /// The bubble was clicked: his eyes shut until this week resets.
    public static func dismiss(_ weekly: UsageLimit, in defaults: UserDefaults = .standard) {
        guard let resetsAt = weekly.resetsAt else { return }
        defaults.set(resetsAt.timeIntervalSince1970, forKey: shutUntilKey)
    }

    /// Whether his eyes are shut: a click this week, before its reset.
    public static func eyesShut(now: Date, in defaults: UserDefaults = .standard) -> Bool {
        let until = defaults.double(forKey: shutUntilKey)
        return until > 0 && now.timeIntervalSince1970 < until
    }

    /// The standard ease-in-out bounce, 0…1 over 0…1.
    static func bounceInOut(_ x: Double) -> Double {
        x < 0.5 ? (1 - bounceOut(1 - 2 * x)) / 2 : (1 + bounceOut(2 * x - 1)) / 2
    }

    static func bounceOut(_ x: Double) -> Double {
        let n = 7.5625, d = 2.75
        if x < 1 / d { return n * x * x }
        if x < 2 / d { let y = x - 1.5 / d; return n * y * y + 0.75 }
        if x < 2.5 / d { let y = x - 2.25 / d; return n * y * y + 0.9375 }
        let y = x - 2.625 / d
        return n * y * y + 0.984375
    }
}
