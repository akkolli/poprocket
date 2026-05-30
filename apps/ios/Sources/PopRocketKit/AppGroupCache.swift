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
        try data.write(to: cardsURL(), options: [.atomic])
    }

    public func loadCards() throws -> CachedCards? {
        let url = try cardsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try PopRocketCoding.decoder.decode(CachedCards.self, from: data)
    }

    @discardableResult
    public func saveDashboardState(
        bridgeID: String,
        healthMonitors: [HealthMonitor],
        wolTargets: [WOLTarget],
        healthMonitorsUpdatedAt: Date? = nil,
        wolTargetsUpdatedAt: Date? = nil
    ) throws -> CachedDashboardState {
        let state = CachedDashboardState(
            bridgeID: bridgeID,
            healthMonitors: healthMonitors,
            wolTargets: wolTargets,
            writtenAt: Date(),
            healthMonitorsUpdatedAt: healthMonitorsUpdatedAt,
            wolTargetsUpdatedAt: wolTargetsUpdatedAt
        )
        let data = try PopRocketCoding.encoder.encode(state)
        try data.write(to: dashboardStateURL(bridgeID: bridgeID), options: [.atomic])
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

    private func cardsURL() throws -> URL {
        try cacheDirectory().appendingPathComponent("cards.json")
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

public struct CachedDashboardState: Codable, Equatable {
    public let bridgeID: String
    public let healthMonitors: [HealthMonitor]
    public let wolTargets: [WOLTarget]
    public let writtenAt: Date
    public let healthMonitorsUpdatedAt: Date?
    public let wolTargetsUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case bridgeID = "bridge_id"
        case healthMonitors = "health_monitors"
        case wolTargets = "wol_targets"
        case writtenAt = "written_at"
        case healthMonitorsUpdatedAt = "health_monitors_updated_at"
        case wolTargetsUpdatedAt = "wol_targets_updated_at"
    }
}
