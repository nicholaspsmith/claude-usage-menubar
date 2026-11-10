// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import ClaudeUsageCore

final class UsageExportTests: XCTestCase {
    private func scratchURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-export-\(UUID().uuidString)/nested/usage.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        return url
    }

    private func read(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // The file is what scripts and agents read: both windows, as percentages
    // and ISO-8601 reset times, plus how long until each reset.
    func testWritesBothWindows() throws {
        let url = scratchURL()
        let now = Date(timeIntervalSince1970: 1_794_286_000)
        let snapshot = LimitsSnapshot(limits: [
            UsageLimit(label: "Session (5-hour)", fraction: 0.93, resetsAt: now.addingTimeInterval(3_600)),
            UsageLimit(label: "Weekly (7-day)", fraction: 0.29, resetsAt: now.addingTimeInterval(86_400 * 4)),
        ], planLabel: "Max 5x")
        UsageExport.write(snapshot, updatedAt: now, to: url)

        let json = try read(url)
        XCTAssertEqual(json["schema"] as? Int, 1)
        XCTAssertEqual(json["updatedAt"] as? String, "2026-11-10T04:46:40Z")
        XCTAssertEqual(json["plan"] as? String, "Max 5x")
        XCTAssertEqual(json["status"] as? String, "")
        let limits = try XCTUnwrap(json["limits"] as? [[String: Any]])
        XCTAssertEqual(limits.count, 2)
        XCTAssertEqual(limits[0]["window"] as? String, "session")
        XCTAssertEqual(limits[0]["label"] as? String, "Session (5-hour)")
        XCTAssertEqual(limits[0]["percent"] as? Int, 93)
        XCTAssertEqual(limits[0]["resetsAt"] as? String, "2026-11-10T05:46:40Z")
        XCTAssertEqual(limits[0]["resetsInSeconds"] as? Int, 3_600)
        XCTAssertEqual(limits[1]["window"] as? String, "weekly")
        XCTAssertEqual(limits[1]["percent"] as? Int, 29)
        XCTAssertEqual(limits[1]["resetsInSeconds"] as? Int, 86_400 * 4)
    }

    // No numbers (signed out, offline before the first probe): the file still
    // exists and says why, so a reader can tell "unknown" from "0%".
    func testWritesStatusWhenNoLimits() throws {
        let url = scratchURL()
        UsageExport.write(LimitsSnapshot(statusText: "Not signed in"), updatedAt: Date(timeIntervalSince1970: 0), to: url)
        let json = try read(url)
        XCTAssertEqual(json["status"] as? String, "Not signed in")
        XCTAssertEqual((json["limits"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(json["plan"] as? String, "")
    }

    // Percent rounds to the nearest whole number and a missing reset is null.
    func testRoundingAndMissingReset() throws {
        let url = scratchURL()
        UsageExport.write(LimitsSnapshot(limits: [UsageLimit(label: "Something else", fraction: 0.456, resetsAt: nil)]),
                          updatedAt: Date(timeIntervalSince1970: 0), to: url)
        let limit = try XCTUnwrap((try read(url)["limits"] as? [[String: Any]])?.first)
        XCTAssertEqual(limit["window"] as? String, "other")
        XCTAssertEqual(limit["percent"] as? Int, 46)
        XCTAssertTrue(limit["resetsAt"] is NSNull)
        XCTAssertTrue(limit["resetsInSeconds"] is NSNull)
    }

    func testDefaultLocationIsApplicationSupport() {
        XCTAssertTrue(UsageExport.defaultURL.path.hasSuffix("Library/Application Support/ClaudeUsage/usage.json"))
    }
}
