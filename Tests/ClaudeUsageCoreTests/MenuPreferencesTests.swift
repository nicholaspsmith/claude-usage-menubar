// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ClaudeUsageCore

final class MenuPreferencesTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "MenuPreferencesTests-\(UUID().uuidString)")!
    }

    // The sessions list is opt-in: a fresh install shows limits only.
    func testSessionsHiddenByDefault() {
        XCTAssertFalse(MenuPreferences.showSessions(in: defaults()))
    }

    func testShowSessionsRoundTrips() {
        let d = defaults()
        MenuPreferences.setShowSessions(true, in: d)
        XCTAssertTrue(MenuPreferences.showSessions(in: d))
        MenuPreferences.setShowSessions(false, in: d)
        XCTAssertFalse(MenuPreferences.showSessions(in: d))
    }
}
