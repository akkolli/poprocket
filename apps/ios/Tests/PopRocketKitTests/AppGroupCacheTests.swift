import XCTest
@testable import PopRocketKit

final class AppGroupCacheTests: XCTestCase {
    func testDashboardStateIsBridgeScoped() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let checkedAt = Date(timeIntervalSince1970: 100)
        let monitor = HealthMonitor(
            id: "ssh",
            name: "SSH",
            kind: "tcp",
            host: "pluto",
            port: 22,
            url: nil,
            timeoutSeconds: 3,
            source: "user",
            status: "up",
            responseTimeMS: 12,
            message: nil,
            checkedAt: checkedAt,
            statusChangedAt: checkedAt,
            createdAt: nil,
            updatedAt: nil
        )
        let target = WOLTarget(
            id: "neptune",
            name: "Neptune",
            mac: "02:00:5e:10:00:01",
            ipAddress: "192.168.1.50",
            broadcastIP: "192.168.1.255",
            udpPort: 9,
            source: "user",
            createdAt: nil,
            updatedAt: nil
        )

        let monitorUpdatedAt = Date(timeIntervalSince1970: 200)
        let targetUpdatedAt = Date(timeIntervalSince1970: 300)
        let saved = try cache.saveDashboardState(
            bridgeID: "bridge/dev",
            healthMonitors: [monitor],
            wolTargets: [target],
            healthMonitorsUpdatedAt: monitorUpdatedAt,
            wolTargetsUpdatedAt: targetUpdatedAt
        )

        let loaded = try XCTUnwrap(cache.loadDashboardState(bridgeID: "bridge/dev"))
        XCTAssertEqual(loaded.bridgeID, "bridge/dev")
        XCTAssertEqual(loaded.healthMonitors, [monitor])
        XCTAssertEqual(loaded.wolTargets, [target])
        XCTAssertLessThan(abs(loaded.writtenAt.timeIntervalSince(saved.writtenAt)), 1)
        XCTAssertEqual(loaded.healthMonitorsUpdatedAt, monitorUpdatedAt)
        XCTAssertEqual(loaded.wolTargetsUpdatedAt, targetUpdatedAt)
        XCTAssertNil(try cache.loadDashboardState(bridgeID: "other"))
    }

    func testDashboardStateSectionTimestampsAreOptionalForLegacyCaches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)

        _ = try cache.saveDashboardState(bridgeID: "bridge/dev", healthMonitors: [], wolTargets: [])

        let loaded = try XCTUnwrap(cache.loadDashboardState(bridgeID: "bridge/dev"))
        XCTAssertNil(loaded.healthMonitorsUpdatedAt)
        XCTAssertNil(loaded.wolTargetsUpdatedAt)
    }

    func testDashboardStateCanUpdateOneSectionWithoutFresheningTheOther() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let oldTargetUpdatedAt = Date(timeIntervalSince1970: 400)
        let newMonitorUpdatedAt = Date(timeIntervalSince1970: 500)
        let target = WOLTarget(
            id: "neptune",
            name: "Neptune",
            mac: "02:00:5e:10:00:01",
            ipAddress: "192.168.1.50",
            broadcastIP: "192.168.1.255",
            udpPort: 9,
            source: "user",
            createdAt: nil,
            updatedAt: nil
        )
        let monitor = HealthMonitor(
            id: "ssh",
            name: "SSH",
            kind: "tcp",
            host: "pluto",
            port: 22,
            url: nil,
            timeoutSeconds: 3,
            source: "user",
            status: "up",
            responseTimeMS: 12,
            message: nil,
            checkedAt: newMonitorUpdatedAt,
            statusChangedAt: newMonitorUpdatedAt,
            createdAt: nil,
            updatedAt: nil
        )

        _ = try cache.saveDashboardState(
            bridgeID: "bridge/dev",
            healthMonitors: [monitor],
            wolTargets: [target],
            healthMonitorsUpdatedAt: newMonitorUpdatedAt,
            wolTargetsUpdatedAt: oldTargetUpdatedAt
        )

        let loaded = try XCTUnwrap(cache.loadDashboardState(bridgeID: "bridge/dev"))
        XCTAssertEqual(loaded.healthMonitorsUpdatedAt, newMonitorUpdatedAt)
        XCTAssertEqual(loaded.wolTargetsUpdatedAt, oldTargetUpdatedAt)
    }
}
