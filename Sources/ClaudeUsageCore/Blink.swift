// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// The owl's once-a-minute blink: how far the lids are shut at each moment.
///
/// Timed on a human spontaneous blink, slowed about 1.5× so it reads in the
/// menu bar. Measured blinks average ~330 ms: the lid falls in ~90 ms, stays
/// shut 10–50 ms, and takes ~240 ms — nearly three times as long — to come
/// back up. Falling, it starts slowly and accelerates (peak speed as it
/// crosses the eye, stopping only when it lands), so the close is an ease-in.
/// Rising, it is quickest at the start and settles with a long tail, so the
/// open is an ease-out. At 1× the blink is barely a flicker on a 22 pt icon.
public enum Blink {
    public static let closing: TimeInterval = 0.14
    public static let hold: TimeInterval = 0.05
    public static let opening: TimeInterval = 0.36
    public static var duration: TimeInterval { closing + hold + opening }

    /// How shut the lids are `elapsed` seconds into the blink: 0 open, 1 shut.
    /// `nil` once the blink is over, which ends the animation.
    public static func closure(at elapsed: TimeInterval) -> Double? {
        if elapsed < 0 { return 0 }
        if elapsed < closing {
            let p = elapsed / closing
            return p * p * p
        }
        if elapsed <= closing + hold { return 1 }
        if elapsed < duration {
            let p = (elapsed - closing - hold) / opening
            return pow(1 - p, 3)
        }
        return nil
    }
}
