import Foundation
import CryptoKit

public struct NotificationActionRouter {
    private let bridgeClient: BridgeClient
    private let keychain: KeychainStore

    public init(bridgeClient: BridgeClient = BridgeClient(), keychain: KeychainStore = KeychainStore()) {
        self.bridgeClient = bridgeClient
        self.keychain = keychain
    }

    public func route(actionID: String, eventID: String?, confirmed: Bool) async throws {
        guard let credential = try keychain.load(PairingCredential.self, account: "active_pairing") else {
            throw URLError(.userAuthenticationRequired)
        }
        var envelope = ActionEnvelope(
            actionRunID: "run_\(UUID().uuidString.lowercased())",
            eventID: eventID,
            actionID: actionID,
            actorDeviceID: credential.deviceID,
            idempotencyKey: eventID.map { "\($0):\(actionID)" },
            confirmed: confirmed
        )
        if let keyData = try keychain.load(Data.self, account: "device_private_key") {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
            try ActionSigner.sign(&envelope, privateKey: privateKey)
        }
        try await bridgeClient.sendAction(envelope, credential: credential)
    }
}
