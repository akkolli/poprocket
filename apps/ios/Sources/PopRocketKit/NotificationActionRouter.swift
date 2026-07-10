import CryptoKit
import Foundation

protocol BridgeCredentialProviding {
    func credential(id bridgeID: String?) throws -> PairingCredential?
    func existingDevicePrivateKey() throws -> Curve25519.Signing.PrivateKey?
}

extension BridgeCredentialStore: BridgeCredentialProviding {}

public struct NotificationActionRouter {
    private let bridgeClient: BridgeClient
    private let bridgeStore: BridgeCredentialProviding

    public init(bridgeClient: BridgeClient = BridgeClient(), keychain: KeychainStore = KeychainStore()) {
        self.init(bridgeClient: bridgeClient, bridgeStore: BridgeCredentialStore(keychain: keychain))
    }

    init(bridgeClient: BridgeClient = BridgeClient(), bridgeStore: BridgeCredentialProviding) {
        self.bridgeClient = bridgeClient
        self.bridgeStore = bridgeStore
    }

    public func route(
        actionID: String,
        eventID: String?,
        confirmed: Bool,
        bridgeID: String? = nil,
        parameters: [String: String]? = nil
    ) async throws -> ActionResult {
        guard let credential = try bridgeStore.credential(id: bridgeID) else {
            throw URLError(.userAuthenticationRequired)
        }
        var envelope = ActionEnvelope(
            actionRunID: "run_\(UUID().uuidString.lowercased())",
            eventID: eventID,
            actionID: actionID,
            actorDeviceID: credential.deviceID,
            idempotencyKey: eventID.map { "\($0):\(actionID)" },
            confirmed: confirmed,
            parameters: parameters
        )
        guard let privateKey = try bridgeStore.existingDevicePrivateKey() else {
            throw BridgeSigningKeyError()
        }
        try ActionSigner.sign(&envelope, privateKey: privateKey)
        return try await bridgeClient.sendAction(envelope, credential: credential)
    }
}
