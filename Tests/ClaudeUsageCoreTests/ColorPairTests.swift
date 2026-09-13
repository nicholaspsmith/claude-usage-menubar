import XCTest
@testable import ClaudeUsageCore

final class ColorPairTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "ColorPairTests-\(UUID().uuidString)")!
    }

    // The whole point of a pair is that the two windows can be told apart.
    func testEveryPairHasTwoDifferentColours() {
        XCTAssertEqual(ColorPair.presets.count, 4)
        for pair in ColorPair.presets {
            XCTAssertNotEqual(pair.sessionHex.uppercased(), pair.weeklyHex.uppercased(), pair.name)
        }
        XCTAssertEqual(Set(ColorPair.presets.map(\.id)).count, ColorPair.presets.count)
    }

    // The default keeps the purple session colour the app has always drawn.
    func testDefaultKeepsThePurple() {
        XCTAssertEqual(ColorPair.default.sessionHex.uppercased(), "#B18EEE")
        XCTAssertEqual(ColorPair.stored(in: defaults()), ColorPair.default)
    }

    func testChoiceRoundTrips() {
        let d = defaults()
        let chosen = ColorPair.presets[2]
        chosen.save(to: d)
        XCTAssertEqual(ColorPair.stored(in: d), chosen)
    }

    // A preference outlives the build that wrote it.
    func testUnknownIdFallsBackToDefault() {
        let d = defaults()
        d.set("sepia-and-ochre", forKey: ColorPair.key)
        XCTAssertEqual(ColorPair.stored(in: d), ColorPair.default)
    }
}
