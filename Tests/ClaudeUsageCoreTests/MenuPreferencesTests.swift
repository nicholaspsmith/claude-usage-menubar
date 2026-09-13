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
