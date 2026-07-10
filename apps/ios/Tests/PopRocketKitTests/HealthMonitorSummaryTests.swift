import XCTest
@testable import PopRocketKit

final class HealthMonitorSummaryTests: XCTestCase {
    func testSummaryPrioritizesAttentionThenSortsByName() {
        let monitors = [
            monitor(id: "up-z", name: "Zulu", status: "up"),
            monitor(id: "unknown", name: "Beta", status: "checking"),
            monitor(id: "down-z", name: "Zulu", status: "down"),
            monitor(id: "down-a", name: "Alpha", status: "down")
        ]

        let summary = HealthMonitorSummary(monitors: monitors)

        XCTAssertEqual(summary.sortedMonitors.map(\.id), ["down-a", "down-z", "unknown", "up-z"])
        XCTAssertEqual(summary.downCount, 2)
        XCTAssertEqual(summary.unknownCount, 1)
        XCTAssertEqual(summary.upCount, 1)
        XCTAssertEqual(summary.alertMonitors.map(\.id), ["down-a", "down-z", "unknown"])
    }

    private func monitor(id: String, name: String, status: String) -> HealthMonitor {
        HealthMonitor(
            id: id,
            name: name,
            kind: "tcp",
            host: "server.local",
            port: 22,
            url: nil,
            timeoutSeconds: 3,
            source: "test",
            status: status,
            responseTimeMS: nil,
            message: nil,
            checkedAt: nil,
            statusChangedAt: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }
}
