import Foundation

public final class AppGroupCache {
    public static let defaultGroupID = "group.com.poprocket.app"

    private let groupID: String
    private let fileManager: FileManager

    public init(groupID: String = AppGroupCache.defaultGroupID, fileManager: FileManager = .default) {
        self.groupID = groupID
        self.fileManager = fileManager
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

    private func cardsURL() throws -> URL {
        let directory: URL
        if let appGroup = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            directory = appGroup
        } else {
            directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cards.json")
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
