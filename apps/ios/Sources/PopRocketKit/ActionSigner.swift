import CryptoKit
import Foundation

public enum ActionSigner {
    public static func makePrivateKey() -> Curve25519.Signing.PrivateKey {
        Curve25519.Signing.PrivateKey()
    }

    public static func publicKeyBase64(for privateKey: Curve25519.Signing.PrivateKey) -> String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    public static func sign(_ envelope: inout ActionEnvelope, privateKey: Curve25519.Signing.PrivateKey) throws {
        let message = canonicalMessage(envelope)
        let signature = try privateKey.signature(for: Data(message.utf8))
        envelope.signature = signature.base64EncodedString()
    }

    public static func canonicalMessage(_ envelope: ActionEnvelope) -> String {
        var fields: [String] = []
        fields.append(jsonPair("action_run_id", envelope.actionRunID))
        if let eventID = envelope.eventID, !eventID.isEmpty {
            fields.append(jsonPair("event_id", eventID))
        }
        fields.append(jsonPair("action_id", envelope.actionID))
        fields.append(jsonPair("actor_device_id", envelope.actorDeviceID))
        if let key = envelope.idempotencyKey, !key.isEmpty {
            fields.append(jsonPair("idempotency_key", key))
        }
        if envelope.confirmed {
            fields.append("\"confirmed\":true")
        }
        if let parameters = envelope.parameters, !parameters.isEmpty {
            fields.append(jsonObject("parameters", parameters))
        }
        fields.append(jsonPair("created_at", RFC3339.string(from: envelope.createdAt)))
        return "{\(fields.joined(separator: ","))}"
    }

    private static func jsonObject(_ key: String, _ value: [String: String]) -> String {
        let pairs = value.keys.sorted().map { name in
            jsonPair(name, value[name] ?? "")
        }
        return "\"\(key)\":{\(pairs.joined(separator: ","))}"
    }

    private static func jsonPair(_ key: String, _ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(key)\":\"\(escaped)\""
    }
}

public enum RFC3339 {
    private static let noFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func string(from date: Date) -> String {
        noFractional.string(from: date)
    }
}
