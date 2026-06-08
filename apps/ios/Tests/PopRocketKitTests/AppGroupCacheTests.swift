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
            host: "server",
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
            id: "desktop",
            name: "Desktop",
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
            bridgeName: "Lab Bridge",
            bridgeReachable: true,
            bridgeStatus: "Online",
            healthMonitors: [monitor],
            wolTargets: [target],
            healthMonitorsUpdatedAt: monitorUpdatedAt,
            wolTargetsUpdatedAt: targetUpdatedAt
        )

        let loaded = try XCTUnwrap(cache.loadDashboardState(bridgeID: "bridge/dev"))
        XCTAssertEqual(loaded.bridgeID, "bridge/dev")
        XCTAssertEqual(loaded.bridgeName, "Lab Bridge")
        XCTAssertEqual(loaded.bridgeReachable, true)
        XCTAssertEqual(loaded.bridgeStatus, "Online")
        XCTAssertEqual(loaded.healthMonitors, [monitor])
        XCTAssertEqual(loaded.wolTargets, [target])
        XCTAssertLessThan(abs(loaded.writtenAt.timeIntervalSince(saved.writtenAt)), 1)
        XCTAssertEqual(loaded.healthMonitorsUpdatedAt, monitorUpdatedAt)
        XCTAssertEqual(loaded.wolTargetsUpdatedAt, targetUpdatedAt)

        let active = try XCTUnwrap(cache.loadActiveDashboardState())
        XCTAssertEqual(active.bridgeID, "bridge/dev")
        XCTAssertEqual(active.bridgeName, "Lab Bridge")
        XCTAssertEqual(active.bridgeReachable, true)
        XCTAssertEqual(active.bridgeStatus, "Online")
        XCTAssertEqual(active.healthMonitors, [monitor])
        XCTAssertEqual(active.wolTargets, [target])
        XCTAssertEqual(active.healthMonitorsUpdatedAt, monitorUpdatedAt)
        XCTAssertEqual(active.wolTargetsUpdatedAt, targetUpdatedAt)
        try cache.clearActiveDashboardState()
        XCTAssertNil(try cache.loadActiveDashboardState())
        XCTAssertNil(try cache.loadDashboardState(bridgeID: "other"))
    }

    func testDashboardStateSectionTimestampsAreOptionalForLegacyCaches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)

        _ = try cache.saveDashboardState(bridgeID: "bridge/dev", healthMonitors: [], wolTargets: [])

        let loaded = try XCTUnwrap(cache.loadDashboardState(bridgeID: "bridge/dev"))
        XCTAssertNil(loaded.bridgeName)
        XCTAssertNil(loaded.bridgeReachable)
        XCTAssertNil(loaded.bridgeStatus)
        XCTAssertNil(loaded.healthMonitorsUpdatedAt)
        XCTAssertNil(loaded.wolTargetsUpdatedAt)
    }

    func testDashboardStateNormalizesLegacyBridgeNameForWidgets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)

        _ = try cache.saveDashboardState(
            bridgeID: "bridge/dev",
            bridgeName: "PopRocket Pi Bridge",
            healthMonitors: [],
            wolTargets: []
        )

        let loaded = try XCTUnwrap(cache.loadDashboardState(bridgeID: "bridge/dev"))
        let active = try XCTUnwrap(cache.loadActiveDashboardState())
        XCTAssertEqual(loaded.bridgeName, "Local Bridge")
        XCTAssertEqual(active.bridgeName, "Local Bridge")
    }

    func testDashboardStateBridgeNameCanBeUpdatedWithoutLosingCachedSections() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let checkedAt = Date(timeIntervalSince1970: 100)
        let monitorUpdatedAt = Date(timeIntervalSince1970: 200)
        let targetUpdatedAt = Date(timeIntervalSince1970: 300)
        let monitor = HealthMonitor(
            id: "ssh",
            name: "SSH",
            kind: "tcp",
            host: "server",
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
            id: "desktop",
            name: "Desktop",
            mac: "02:00:5e:10:00:01",
            ipAddress: "192.168.1.50",
            broadcastIP: "192.168.1.255",
            udpPort: 9,
            source: "user",
            createdAt: nil,
            updatedAt: nil
        )

        _ = try cache.saveDashboardState(
            bridgeID: "bridge/dev",
            bridgeName: "Old Bridge",
            bridgeReachable: false,
            bridgeStatus: "Connection failed",
            healthMonitors: [monitor],
            wolTargets: [target],
            healthMonitorsUpdatedAt: monitorUpdatedAt,
            wolTargetsUpdatedAt: targetUpdatedAt
        )

        let updated = try XCTUnwrap(cache.updateDashboardBridgeName(bridgeID: "bridge/dev", bridgeName: "Rack Bridge"))
        let loaded = try XCTUnwrap(cache.loadDashboardState(bridgeID: "bridge/dev"))
        let active = try XCTUnwrap(cache.loadActiveDashboardState())

        XCTAssertEqual(updated.bridgeName, "Rack Bridge")
        XCTAssertEqual(loaded.bridgeName, "Rack Bridge")
        XCTAssertEqual(active.bridgeName, "Rack Bridge")
        XCTAssertEqual(loaded.bridgeReachable, false)
        XCTAssertEqual(loaded.bridgeStatus, "Connection failed")
        XCTAssertEqual(active.bridgeReachable, false)
        XCTAssertEqual(active.bridgeStatus, "Connection failed")
        XCTAssertEqual(loaded.healthMonitors, [monitor])
        XCTAssertEqual(loaded.wolTargets, [target])
        XCTAssertEqual(loaded.healthMonitorsUpdatedAt, monitorUpdatedAt)
        XCTAssertEqual(loaded.wolTargetsUpdatedAt, targetUpdatedAt)
    }

    func testCommandShortcutsCanBeSharedWithWidgets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let shortcut = CommandShortcut(
            id: UUID(),
            bridgeID: "bridge/dev",
            name: "Wake Desktop",
            command: "wake-desktop",
            lastStatus: "completed",
            lastResult: "sent",
            lastRunAt: Date(timeIntervalSince1970: 123)
        )

        try cache.saveCommandShortcuts([shortcut])

        let loaded = try XCTUnwrap(cache.loadCommandShortcuts())
        XCTAssertEqual(loaded.shortcuts, [shortcut])
    }

    func testWidgetActionSelectionsCanBeSharedWithWidgets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let selection = WidgetActionSelection(
            id: WidgetActionSelection.id(bridgeID: "bridge/dev", kind: .wol, actionID: "desktop"),
            bridgeID: "bridge/dev",
            kind: .wol,
            actionID: "desktop",
            title: "Wake Desktop",
            subtitle: "192.168.1.50",
            order: 0,
            addedAt: Date(timeIntervalSince1970: 123)
        )

        try cache.saveWidgetActionSelections([selection])

        let loaded = try XCTUnwrap(cache.loadWidgetActionSelections())
        XCTAssertEqual(loaded.selections, [selection])
    }

    func testWidgetActionSelectionRequiresExactTrustedAction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let selection = WidgetActionSelection(
            id: WidgetActionSelection.id(bridgeID: "bridge/dev", kind: .command, actionID: "shortcut-1"),
            bridgeID: "bridge/dev",
            kind: .command,
            actionID: "shortcut-1",
            title: "Restart Service",
            subtitle: "ssh server restart-service",
            order: 0,
            addedAt: Date(timeIntervalSince1970: 123)
        )

        try cache.saveWidgetActionSelections([selection])

        XCTAssertEqual(
            try cache.widgetActionSelection(bridgeID: "bridge/dev", kind: .command, actionID: "shortcut-1"),
            selection
        )
        XCTAssertNil(try cache.widgetActionSelection(bridgeID: "bridge/dev", kind: .wol, actionID: "shortcut-1"))
        XCTAssertNil(try cache.widgetActionSelection(bridgeID: "bridge/other", kind: .command, actionID: "shortcut-1"))
        XCTAssertNil(try cache.widgetActionSelection(bridgeID: "bridge/dev", kind: .command, actionID: "shortcut-2"))
    }

    func testRequireWidgetActionSelectionRejectsUntrustedAction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)

        XCTAssertThrowsError(
            try cache.requireWidgetActionSelection(bridgeID: "bridge/dev", kind: .wol, actionID: "desktop")
        ) { error in
            XCTAssertEqual(error as? WidgetActionAuthorizationError, .notTrusted)
        }
    }

    func testWidgetActionRunRecordsKeepLatestResultPerTrustedAction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let actionID = WidgetActionSelection.id(bridgeID: "bridge/dev", kind: .wol, actionID: "desktop")
        let oldRecord = WidgetActionRunRecord(
            id: actionID,
            bridgeID: "bridge/dev",
            kind: .wol,
            actionID: "desktop",
            title: "Wake Desktop",
            status: "failed",
            message: "offline",
            succeeded: false,
            ranAt: Date(timeIntervalSince1970: 100)
        )
        let newRecord = WidgetActionRunRecord(
            id: actionID,
            bridgeID: "bridge/dev",
            kind: .wol,
            actionID: "desktop",
            title: "Wake Desktop",
            status: "accepted",
            message: "packet sent",
            succeeded: true,
            ranAt: Date(timeIntervalSince1970: 200)
        )

        try cache.recordWidgetActionRun(oldRecord)
        try cache.recordWidgetActionRun(newRecord)

        let loaded = try XCTUnwrap(cache.loadWidgetActionRunRecords())
        XCTAssertEqual(loaded.records, [newRecord])
    }

    func testTrustedWidgetActionRunRecordsOnlyWhenActionIsSelected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let selection = WidgetActionSelection(
            id: WidgetActionSelection.id(bridgeID: "bridge/dev", kind: .command, actionID: "shortcut-1"),
            bridgeID: "bridge/dev",
            kind: .command,
            actionID: "shortcut-1",
            title: "Restart Service",
            subtitle: "ssh server restart-service",
            order: 0,
            addedAt: Date(timeIntervalSince1970: 123)
        )
        try cache.saveWidgetActionSelections([selection])

        let recorded = try cache.recordTrustedWidgetActionRun(
            bridgeID: "bridge/dev",
            kind: .command,
            actionID: "shortcut-1",
            title: "Restart Service",
            status: "completed",
            message: "done",
            succeeded: true,
            ranAt: Date(timeIntervalSince1970: 500)
        )

        let loaded = try XCTUnwrap(cache.loadWidgetActionRunRecords())
        XCTAssertTrue(recorded)
        XCTAssertEqual(loaded.records.count, 1)
        XCTAssertEqual(loaded.records[0].id, selection.id)
        XCTAssertEqual(loaded.records[0].title, "Restart Service")
        XCTAssertTrue(loaded.records[0].succeeded)
    }

    func testTrustedWidgetActionRunRejectsUnselectedAction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)

        let recorded = try cache.recordTrustedWidgetActionRun(
            bridgeID: "bridge/dev",
            kind: .wol,
            actionID: "desktop",
            title: "Wake Desktop",
            status: "completed",
            message: "sent",
            succeeded: true,
            ranAt: Date(timeIntervalSince1970: 500)
        )

        XCTAssertFalse(recorded)
        XCTAssertNil(try cache.loadWidgetActionRunRecords())
    }

    func testActionRunOutcomeDoesNotTreatBridgeFailuresAsSuccess() {
        XCTAssertTrue(ActionRunOutcome.succeeded(status: "completed", duplicate: nil))
        XCTAssertTrue(ActionRunOutcome.succeeded(status: "accepted", duplicate: nil))
        XCTAssertTrue(ActionRunOutcome.succeeded(status: "failed", duplicate: true))
        XCTAssertFalse(ActionRunOutcome.succeeded(status: "failed", duplicate: nil))
        XCTAssertFalse(ActionRunOutcome.succeeded(status: "denied", duplicate: nil))
        XCTAssertEqual(ActionRunOutcome.displayStatus(status: "completed", duplicate: nil), "Sent")
        XCTAssertEqual(ActionRunOutcome.displayStatus(status: "accepted", duplicate: nil), "Accepted")
        XCTAssertEqual(ActionRunOutcome.displayStatus(status: "failed", duplicate: true), "Duplicate")
    }

    func testDashboardStateCanUpdateOneSectionWithoutFresheningTheOther() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poprocket-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AppGroupCache(baseDirectory: directory)
        let oldTargetUpdatedAt = Date(timeIntervalSince1970: 400)
        let newMonitorUpdatedAt = Date(timeIntervalSince1970: 500)
        let target = WOLTarget(
            id: "desktop",
            name: "Desktop",
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
            host: "server",
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
        let active = try XCTUnwrap(cache.loadActiveDashboardState())
        XCTAssertEqual(loaded.healthMonitorsUpdatedAt, newMonitorUpdatedAt)
        XCTAssertEqual(loaded.wolTargetsUpdatedAt, oldTargetUpdatedAt)
        XCTAssertEqual(active.healthMonitorsUpdatedAt, newMonitorUpdatedAt)
        XCTAssertEqual(active.wolTargetsUpdatedAt, oldTargetUpdatedAt)
    }
}
