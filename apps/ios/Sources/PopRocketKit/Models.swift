import Foundation

public struct PairingPayload: Codable, Equatable {
    public let version: Int
    public let bridgeID: String
    public let bridgeName: String
    public let relayURL: URL?
    public let relayWebSocketURL: URL?
    public let pairingToken: String
    public let bridgePublicKey: String
    public let directURLs: [URL]
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case bridgeID = "bridge_id"
        case bridgeName = "bridge_name"
        case relayURL = "relay_url"
        case relayWebSocketURL = "relay_websocket_url"
        case pairingToken = "pairing_token"
        case bridgePublicKey = "bridge_public_key"
        case directURLs = "direct_urls"
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        bridgeID = try container.decode(String.self, forKey: .bridgeID)
        bridgeName = try container.decode(String.self, forKey: .bridgeName)
        relayURL = try Self.decodeOptionalURL(from: container, forKey: .relayURL)
        relayWebSocketURL = try Self.decodeOptionalURL(from: container, forKey: .relayWebSocketURL)
        pairingToken = try container.decode(String.self, forKey: .pairingToken)
        bridgePublicKey = try container.decode(String.self, forKey: .bridgePublicKey)
        directURLs = try container.decode([URL].self, forKey: .directURLs)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
    }

    private static func decodeOptionalURL(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> URL? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard let url = URL(string: trimmed) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid URL: \(value)"
            )
        }
        return url
    }
}

public struct PairingCredential: Codable, Equatable {
    public let bridgeID: String
    public let bridgeName: String
    public let directURLs: [URL]
    public let relayURL: URL?
    public let relayWebSocketURL: URL?
    public let deviceID: String
    public let scopes: [String]
    public let pairedAt: Date

    public init(
        bridgeID: String,
        bridgeName: String,
        directURLs: [URL],
        relayURL: URL?,
        relayWebSocketURL: URL?,
        deviceID: String,
        scopes: [String],
        pairedAt: Date
    ) {
        self.bridgeID = bridgeID
        self.bridgeName = bridgeName
        self.directURLs = directURLs
        self.relayURL = relayURL
        self.relayWebSocketURL = relayWebSocketURL
        self.deviceID = deviceID
        self.scopes = scopes
        self.pairedAt = pairedAt
    }
}

public struct CardSnapshot: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let kind: String
    public let status: String
    public let value: JSONValue?
    public let error: String?
    public let updatedAt: Date
    public let staleAfterSeconds: Int
    public let stale: Bool
    public let actions: [CardAction]?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, status, value, error, stale, actions
        case updatedAt = "updated_at"
        case staleAfterSeconds = "stale_after_seconds"
    }
}

public struct CardAction: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let kind: String
}

public struct CardsResponse: Codable {
    public let cards: [CardSnapshot]
}

public struct PairingStartResponse: Codable {
    public let pairingToken: String
    public let expiresAt: Date
    public let payload: PairingPayload
    public let qrPayload: String

    enum CodingKeys: String, CodingKey {
        case pairingToken = "pairing_token"
        case expiresAt = "expires_at"
        case payload
        case qrPayload = "qr_payload"
    }
}

public struct WOLTarget: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let mac: String
    public let ipAddress: String?
    public let broadcastIP: String
    public let udpPort: Int
    public let source: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, mac, source
        case ipAddress = "ip_address"
        case broadcastIP = "broadcast_ip"
        case udpPort = "udp_port"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct WOLTargetsResponse: Codable {
    public let targets: [WOLTarget]
}

public struct WOLTargetResponse: Codable {
    public let target: WOLTarget
}

public struct WOLTargetRequest: Codable, Equatable {
    public let name: String
    public let mac: String
    public let ipAddress: String?
    public let broadcastIP: String?
    public let udpPort: Int?

    public init(name: String, mac: String, ipAddress: String?, broadcastIP: String?, udpPort: Int?) {
        self.name = name
        self.mac = mac
        self.ipAddress = ipAddress
        self.broadcastIP = broadcastIP
        self.udpPort = udpPort
    }

    enum CodingKeys: String, CodingKey {
        case name, mac
        case ipAddress = "ip_address"
        case broadcastIP = "broadcast_ip"
        case udpPort = "udp_port"
    }
}

public struct HomelabEvent: Codable, Equatable, Identifiable {
    public var id: String { eventID }
    public let eventID: String
    public let severity: String
    public let title: String
    public let body: String
    public let source: String?
    public let actions: [EventAction]
    public let cardIDs: [String]
    public let ttlSeconds: Int
    public let createdAt: Date
    public let idempotencyKey: String?

    enum CodingKeys: String, CodingKey {
        case severity, title, body, source, actions
        case eventID = "event_id"
        case cardIDs = "card_ids"
        case ttlSeconds = "ttl_seconds"
        case createdAt = "created_at"
        case idempotencyKey = "idempotency_key"
    }
}

public struct EventAction: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let kind: String
    public let scope: String?
    public let requiresConfirmation: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, kind, scope
        case requiresConfirmation = "requires_confirmation"
    }
}

public struct ActionEnvelope: Codable, Equatable {
    public var actionRunID: String
    public var eventID: String?
    public var actionID: String
    public var actorDeviceID: String
    public var idempotencyKey: String?
    public var confirmed: Bool
    public var parameters: [String: String]?
    public var createdAt: Date
    public var signature: String?

    public init(
        actionRunID: String,
        eventID: String?,
        actionID: String,
        actorDeviceID: String,
        idempotencyKey: String?,
        confirmed: Bool,
        parameters: [String: String]? = nil,
        createdAt: Date = Date(),
        signature: String? = nil
    ) {
        self.actionRunID = actionRunID
        self.eventID = eventID
        self.actionID = actionID
        self.actorDeviceID = actorDeviceID
        self.idempotencyKey = idempotencyKey
        self.confirmed = confirmed
        self.parameters = parameters
        self.createdAt = createdAt
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey {
        case actionRunID = "action_run_id"
        case eventID = "event_id"
        case actionID = "action_id"
        case actorDeviceID = "actor_device_id"
        case idempotencyKey = "idempotency_key"
        case confirmed
        case parameters
        case createdAt = "created_at"
        case signature
    }
}

public struct ActionResult: Codable, Equatable {
    public let actionRunID: String
    public let status: String?
    public let resultMessage: String?
    public let duplicate: Bool?

    enum CodingKeys: String, CodingKey {
        case actionRunID = "action_run_id"
        case status
        case resultMessage = "result_message"
        case duplicate
    }
}

public struct AuditRecord: Codable, Equatable, Identifiable {
    public var id: String { actionRunID }
    public let actionRunID: String
    public let eventID: String?
    public let actionID: String
    public let actorDeviceID: String
    public let status: String
    public let resultMessage: String?
    public let createdAt: Date
    public let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case actionRunID = "action_run_id"
        case eventID = "event_id"
        case actionID = "action_id"
        case actorDeviceID = "actor_device_id"
        case status
        case resultMessage = "result_message"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
        case .bool(let value):
            return value ? "true" : "false"
        case .object:
            return "object"
        case .array(let values):
            return "\(values.count) items"
        case .null:
            return "null"
        }
    }
}

public enum PopRocketCoding {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = DateFormatters.fractional.date(from: value) ?? DateFormatters.plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RFC3339 date: \(value)")
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RFC3339.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private enum DateFormatters {
    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
