import Foundation

public struct NotificationActionRouter {
    private let bridgeClient: BridgeClient
    private let bridgeStore: BridgeCredentialStore

    public init(bridgeClient: BridgeClient = BridgeClient(), keychain: KeychainStore = KeychainStore()) {
        self.bridgeClient = bridgeClient
        self.bridgeStore = BridgeCredentialStore(keychain: keychain)
    }

    public func route(actionID: String, eventID: String?, confirmed: Bool, bridgeID: String? = nil) async throws {
        guard let credential = try bridgeStore.credential(id: bridgeID) else {
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
        if let privateKey = try bridgeStore.existingDevicePrivateKey() {
            try ActionSigner.sign(&envelope, privateKey: privateKey)
        }
        try await bridgeClient.sendAction(envelope, credential: credential)
    }
}
