import XCTest
import CryptoKit
@testable import PopRocketKit

final class PairingParserTests: XCTestCase {
    func testParsesJSONPayload() throws {
        let raw = """
        {
          "version": 1,
          "bridge_id": "bridge-dev",
          "bridge_name": "Bridge",
          "relay_url": "https://relay.example.com",
          "pairing_token": "pair_1",
          "bridge_public_key": "pub",
          "direct_urls": ["http://bridge.local:8080"],
          "expires_at": "2099-01-01T00:00:00Z"
        }
        """
        let payload = try PairingParser.parse(raw, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(payload.bridgeID, "bridge-dev")
        XCTAssertEqual(payload.directURLs.first?.host, "bridge.local")
    }

    func testActionSignerMatchesEd25519Vector() throws {
        let seed = Data((0..<32).map { UInt8($0) })
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        var envelope = ActionEnvelope(
            actionRunID: "run_1",
            eventID: "evt_1",
            actionID: "wol:target",
            actorDeviceID: "iphone",
            idempotencyKey: nil,
            confirmed: true,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(ActionSigner.publicKeyBase64(for: privateKey), "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=")
        XCTAssertEqual(
            ActionSigner.canonicalMessage(envelope),
            #"{"action_run_id":"run_1","event_id":"evt_1","action_id":"wol:target","actor_device_id":"iphone","confirmed":true,"created_at":"1970-01-01T00:01:40Z"}"#
        )

        try ActionSigner.sign(&envelope, privateKey: privateKey)

        let signature = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(envelope.signature)))
        XCTAssertEqual(signature.count, 64)
        XCTAssertTrue(privateKey.publicKey.isValidSignature(signature, for: Data(ActionSigner.canonicalMessage(envelope).utf8)))
    }

    func testBridgeCredentialStateUpsertsAndSwitchesActiveBridge() throws {
        var state = BridgeCredentialState()
        let first = credential(id: "pi", name: "Pi")
        let second = credential(id: "lab", name: "Lab")

        state.upsert(first)
        XCTAssertEqual(state.activeCredential?.bridgeID, "pi")

        state.upsert(second)
        XCTAssertEqual(state.bridges.map(\.bridgeID), ["pi", "lab"])
        XCTAssertEqual(state.activeCredential?.bridgeID, "lab")

        try state.activate(id: "pi")
        XCTAssertEqual(state.activeCredential?.bridgeID, "pi")
    }

    func testBridgeCredentialStateRemovalFallsBackToRemainingBridge() {
        var state = BridgeCredentialState(activeBridgeID: "pi", bridges: [
            credential(id: "pi", name: "Pi"),
            credential(id: "lab", name: "Lab")
        ])

        state.remove(id: "pi")

        XCTAssertEqual(state.bridges.map(\.bridgeID), ["lab"])
        XCTAssertEqual(state.activeCredential?.bridgeID, "lab")
    }

    private func credential(id: String, name: String) -> PairingCredential {
        PairingCredential(
            bridgeID: id,
            bridgeName: name,
            directURLs: [URL(string: "http://\(id).local:8080")!],
            relayURL: nil,
            relayWebSocketURL: nil,
            deviceID: "device",
            scopes: ["wol:wake:*"],
            pairedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
