import Foundation

public final class AppGroupCache {
    public static let defaultGroupID = "group.com.poprocket.app"

    private let groupID: String
    private let fileManager: FileManager
    private let baseDirectory: URL?

    public init(
        groupID: String = AppGroupCache.defaultGroupID,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.groupID = groupID
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    public func saveCards(_ cards: [CardSnapshot]) throws {
        let data = try PopRocketCoding.encoder.encode(CachedCards(cards: cards, writtenAt: Date()))
        try writeCacheData(data, to: cardsURL())
    }

    public func loadCards() throws -> CachedCards? {
        let url = try cardsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try PopRocketCoding.decoder.decode(CachedCards.self, from: data)
    }

    public func saveCommandShortcuts(_ shortcuts: [CommandShortcut]) throws {
        let data = try PopRocketCoding.encoder.encode(CachedCommandShortcuts(shortcuts: shortcuts, writtenAt: Date()))
        try writeCacheData(data, to: commandShortcutsURL())
    }

    public func loadCommandShortcuts() throws -> CachedCommandShortcuts? {
        let url = try commandShortcutsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try PopRocketCoding.decoder.decode(CachedCommandShortcuts.self, from: data)
    }

    public func saveWidgetActionSelections(_ selections: [WidgetActionSelection]) throws {
        let data = try PopRocketCoding.encoder.encode(CachedWidgetActionSelections(selections: selections, writtenAt: Date()))
        try writeCacheData(data, to: widgetActionSelectionsURL())
    }

    public func loadWidgetActionSelections() throws -> CachedWidgetActionSelections? {
        let url = try widgetActionSelectionsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try PopRocketCoding.decoder.decode(CachedWidgetActionSelections.self, from: data)
    }

    public func widgetActionSelection(
        bridgeID: String,
        kind: WidgetActionKind,
        actionID: String
    ) throws -> WidgetActionSelection? {
        let selectionID = WidgetActionSelection.id(bridgeID: bridgeID, kind: kind, actionID: actionID)
        return try loadWidgetActionSelections()?.selections.first { selection in
            selection.id == selectionID &&
                selection.bridgeID == bridgeID &&
                selection.kind == kind &&
                selection.actionID == actionID
        }
    }

    public func requireWidgetActionSelection(
        bridgeID: String,
        kind: WidgetActionKind,
        actionID: String
    ) throws -> WidgetActionSelection {
        guard let selection = try widgetActionSelection(bridgeID: bridgeID, kind: kind, actionID: actionID) else {
            throw WidgetActionAuthorizationError.notTrusted
        }
        return selection
    }

    public func saveWidgetActionRunRecords(_ records: [WidgetActionRunRecord]) throws {
        let data = try PopRocketCoding.encoder.encode(CachedWidgetActionRunRecords(records: records, writtenAt: Date()))
        try writeCacheData(data, to: widgetActionRunRecordsURL())
    }

    public func loadWidgetActionRunRecords() throws -> CachedWidgetActionRunRecords? {
        let url = try widgetActionRunRecordsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try PopRocketCoding.decoder.decode(CachedWidgetActionRunRecords.self, from: data)
    }

    public func recordWidgetActionRun(_ record: WidgetActionRunRecord, limit: Int = 20) throws {
        var records = (try loadWidgetActionRunRecords()?.records ?? [])
            .filter { $0.id != record.id }
        records.append(record)
        records.sort { lhs, rhs in
            lhs.ranAt > rhs.ranAt
        }
        try saveWidgetActionRunRecords(Array(records.prefix(max(1, limit))))
    }

    @discardableResult
    public func recordTrustedWidgetActionRun(
        bridgeID: String,
        kind: WidgetActionKind,
        actionID: String,
        title: String,
        status: String,
        message: String?,
        succeeded: Bool,
        ranAt: Date = Date(),
        limit: Int = 20
    ) throws -> Bool {
        guard try widgetActionSelection(bridgeID: bridgeID, kind: kind, actionID: actionID) != nil else {
            return false
        }
        let record = WidgetActionRunRecord(
            id: WidgetActionSelection.id(bridgeID: bridgeID, kind: kind, actionID: actionID),
            bridgeID: bridgeID,
            kind: kind,
            actionID: actionID,
            title: title,
            status: status,
            message: message,
            succeeded: succeeded,
            ranAt: ranAt
        )
        try recordWidgetActionRun(record, limit: limit)
        return true
    }

    @discardableResult
    public func saveDashboardState(
        bridgeID: String,
        bridgeName: String? = nil,
        bridgeReachable: Bool? = nil,
        bridgeStatus: String? = nil,
        healthMonitors: [HealthMonitor],
        wolTargets: [WOLTarget],
        healthMonitorsUpdatedAt: Date? = nil,
        wolTargetsUpdatedAt: Date? = nil
    ) throws -> CachedDashboardState {
        let state = CachedDashboardState(
            bridgeID: bridgeID,
            bridgeName: bridgeName,
            bridgeReachable: bridgeReachable,
            bridgeStatus: bridgeStatus,
            healthMonitors: healthMonitors,
            wolTargets: wolTargets,
            writtenAt: Date(),
            healthMonitorsUpdatedAt: healthMonitorsUpdatedAt,
            wolTargetsUpdatedAt: wolTargetsUpdatedAt
        )
        let data = try PopRocketCoding.encoder.encode(state)
        try writeCacheData(data, to: dashboardStateURL(bridgeID: bridgeID))
        try writeCacheData(data, to: activeDashboardStateURL())
        return state
    }

    public func loadDashboardState(bridgeID: String) throws -> CachedDashboardState? {
        let url = try dashboardStateURL(bridgeID: bridgeID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let state = try PopRocketCoding.decoder.decode(CachedDashboardState.self, from: data)
        guard state.bridgeID == bridgeID else {
            return nil
        }
        return state
    }

    public func loadActiveDashboardState() throws -> CachedDashboardState? {
        let url = try activeDashboardStateURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try PopRocketCoding.decoder.decode(CachedDashboardState.self, from: data)
    }

    @discardableResult
    public func updateDashboardBridgeName(bridgeID: String, bridgeName: String?) throws -> CachedDashboardState? {
        guard let existing = try loadDashboardState(bridgeID: bridgeID) else {
            return nil
        }
        return try saveDashboardState(
            bridgeID: bridgeID,
            bridgeName: bridgeName,
            bridgeReachable: existing.bridgeReachable,
            bridgeStatus: existing.bridgeStatus,
            healthMonitors: existing.healthMonitors,
            wolTargets: existing.wolTargets,
            healthMonitorsUpdatedAt: existing.healthMonitorsUpdatedAt,
            wolTargetsUpdatedAt: existing.wolTargetsUpdatedAt
        )
    }

    public func clearActiveDashboardState() throws {
        let url = try activeDashboardStateURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func cardsURL() throws -> URL {
        try cacheDirectory().appendingPathComponent("cards.json")
    }

    private func commandShortcutsURL() throws -> URL {
        try cacheDirectory().appendingPathComponent("command-shortcuts.json")
    }

    private func widgetActionSelectionsURL() throws -> URL {
        try cacheDirectory().appendingPathComponent("widget-action-selections.json")
    }

    private func widgetActionRunRecordsURL() throws -> URL {
        try cacheDirectory().appendingPathComponent("widget-action-runs.json")
    }

    private func activeDashboardStateURL() throws -> URL {
        try cacheDirectory().appendingPathComponent("dashboard-active.json")
    }

    private func dashboardStateURL(bridgeID: String) throws -> URL {
        let filename = "dashboard-\(Self.safeFilename(bridgeID)).json"
        return try cacheDirectory().appendingPathComponent(filename)
    }

    private func cacheDirectory() throws -> URL {
        let directory: URL
        if let baseDirectory {
            directory = baseDirectory
        } else if let appGroup = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            directory = appGroup
        } else {
            directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeCacheData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        #endif
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return value
            .unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
    }
}

public struct CachedCards: Codable, Equatable {
    public let cards: [CardSnapshot]
    public let writtenAt: Date

    public var isStale: Bool {
        guard let newest = cards.map(\.updatedAt).max() else {
            return true
        }
        return Date().timeIntervalSince(newest) > Double(cards.map(\.staleAfterSeconds).min() ?? 60)
    }
}

public struct CachedCommandShortcuts: Codable, Equatable {
    public let shortcuts: [CommandShortcut]
    public let writtenAt: Date
}

public struct CachedWidgetActionSelections: Codable, Equatable {
    public let selections: [WidgetActionSelection]
    public let writtenAt: Date
}

public enum WidgetActionAuthorizationError: LocalizedError, Equatable {
    case notTrusted

    public var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "This widget action is not trusted in PopRocket."
        }
    }
}

public struct CachedWidgetActionRunRecords: Codable, Equatable {
    public let records: [WidgetActionRunRecord]
    public let writtenAt: Date
}

public struct CachedDashboardState: Codable, Equatable {
    public let bridgeID: String
    public let bridgeName: String?
    public let bridgeReachable: Bool?
    public let bridgeStatus: String?
    public let healthMonitors: [HealthMonitor]
    public let wolTargets: [WOLTarget]
    public let writtenAt: Date
    public let healthMonitorsUpdatedAt: Date?
    public let wolTargetsUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case bridgeID = "bridge_id"
        case bridgeName = "bridge_name"
        case bridgeReachable = "bridge_reachable"
        case bridgeStatus = "bridge_status"
        case healthMonitors = "health_monitors"
        case wolTargets = "wol_targets"
        case writtenAt = "written_at"
        case healthMonitorsUpdatedAt = "health_monitors_updated_at"
        case wolTargetsUpdatedAt = "wol_targets_updated_at"
    }

    public init(
        bridgeID: String,
        bridgeName: String? = nil,
        bridgeReachable: Bool? = nil,
        bridgeStatus: String? = nil,
        healthMonitors: [HealthMonitor],
        wolTargets: [WOLTarget],
        writtenAt: Date,
        healthMonitorsUpdatedAt: Date? = nil,
        wolTargetsUpdatedAt: Date? = nil
    ) {
        self.bridgeID = bridgeID
        self.bridgeName = Self.normalizedBridgeName(bridgeName)
        self.bridgeReachable = bridgeReachable
        self.bridgeStatus = Self.normalizedBridgeStatus(bridgeStatus)
        self.healthMonitors = healthMonitors
        self.wolTargets = wolTargets
        self.writtenAt = writtenAt
        self.healthMonitorsUpdatedAt = healthMonitorsUpdatedAt
        self.wolTargetsUpdatedAt = wolTargetsUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bridgeID = try container.decode(String.self, forKey: .bridgeID)
        bridgeName = Self.normalizedBridgeName(try container.decodeIfPresent(String.self, forKey: .bridgeName))
        bridgeReachable = try container.decodeIfPresent(Bool.self, forKey: .bridgeReachable)
        bridgeStatus = Self.normalizedBridgeStatus(try container.decodeIfPresent(String.self, forKey: .bridgeStatus))
        healthMonitors = try container.decode([HealthMonitor].self, forKey: .healthMonitors)
        wolTargets = try container.decode([WOLTarget].self, forKey: .wolTargets)
        writtenAt = try container.decode(Date.self, forKey: .writtenAt)
        healthMonitorsUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .healthMonitorsUpdatedAt)
        wolTargetsUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .wolTargetsUpdatedAt)
    }

    private static func normalizedBridgeName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return BridgeNaming.normalizedDisplayName(trimmed)
    }

    private static func normalizedBridgeStatus(_ status: String?) -> String? {
        guard let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct WatchDashboardSnapshot: Codable, Equatable {
    public let bridgeID: String?
    public let bridgeName: String?
    public let bridgeReachable: Bool
    public let bridgeStatus: String
    public let healthMonitors: [HealthMonitor]
    public let wolTargets: [WOLTarget]
    public let updatedAt: Date

    public init(
        bridgeID: String?,
        bridgeName: String?,
        bridgeReachable: Bool,
        bridgeStatus: String,
        healthMonitors: [HealthMonitor],
        wolTargets: [WOLTarget],
        updatedAt: Date
    ) {
        self.bridgeID = bridgeID
        self.bridgeName = bridgeName
        self.bridgeReachable = bridgeReachable
        self.bridgeStatus = bridgeStatus
        self.healthMonitors = healthMonitors
        self.wolTargets = wolTargets
        self.updatedAt = updatedAt
    }
}
