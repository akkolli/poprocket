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

    func testParsesPairingPayloadWithEmptyRelayURL() throws {
        let raw = """
        {
          "version": 1,
          "bridge_id": "bridge-local",
          "bridge_name": "Local Bridge",
          "relay_url": "",
          "pairing_token": "pair_1",
          "bridge_public_key": "pub",
          "direct_urls": ["http://192.0.2.10:6567"],
          "expires_at": "2099-01-01T00:00:00.123456789Z"
        }
        """

        let payload = try PairingParser.parse(raw, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(payload.bridgeID, "bridge-local")
        XCTAssertNil(payload.relayURL)
        XCTAssertEqual(payload.directURLs.first?.port, 6567)
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

    func testActionSignerIncludesParameters() throws {
        let envelope = ActionEnvelope(
            actionRunID: "run_1",
            eventID: nil,
            actionID: "command:run",
            actorDeviceID: "iphone",
            idempotencyKey: nil,
            confirmed: true,
            parameters: ["command": "printf hello"],
            createdAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            ActionSigner.canonicalMessage(envelope),
            #"{"action_run_id":"run_1","action_id":"command:run","actor_device_id":"iphone","confirmed":true,"parameters":{"command":"printf hello"},"created_at":"1970-01-01T00:01:40Z"}"#
        )
    }

    func testRequestSignerMatchesCanonicalReadMessage() throws {
        let seed = Data((0..<32).map { UInt8($0) })
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        var request = BridgeRequestSignature(
            method: "GET",
            path: "/v1/audit",
            query: "limit=8",
            actorDeviceID: "iphone",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            ActionSigner.canonicalMessage(request),
            #"{"method":"GET","path":"/v1/audit","query":"limit=8","actor_device_id":"iphone","created_at":"1970-01-01T00:01:40Z"}"#
        )

        try ActionSigner.sign(&request, privateKey: privateKey)

        let signature = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(request.signature)))
        XCTAssertEqual(signature.count, 64)
        XCTAssertTrue(privateKey.publicKey.isValidSignature(signature, for: Data(ActionSigner.canonicalMessage(request).utf8)))
    }

    func testBridgeCredentialStateUpsertsAndSwitchesActiveBridge() throws {
        var state = BridgeCredentialState()
        let first = credential(id: "bridge-a", name: "Lab Bridge")
        let second = credential(id: "lab", name: "Lab")

        state.upsert(first)
        XCTAssertEqual(state.activeCredential?.bridgeID, "bridge-a")

        state.upsert(second)
        XCTAssertEqual(state.bridges.map(\.bridgeID), ["bridge-a", "lab"])
        XCTAssertEqual(state.activeCredential?.bridgeID, "lab")

        try state.activate(id: "bridge-a")
        XCTAssertEqual(state.activeCredential?.bridgeID, "bridge-a")
    }

    func testBridgeCredentialStateRemovalFallsBackToRemainingBridge() {
        var state = BridgeCredentialState(activeBridgeID: "bridge-a", bridges: [
            credential(id: "bridge-a", name: "Lab Bridge"),
            credential(id: "lab", name: "Lab")
        ])

        state.remove(id: "bridge-a")

        XCTAssertEqual(state.bridges.map(\.bridgeID), ["lab"])
        XCTAssertEqual(state.activeCredential?.bridgeID, "lab")
    }

    func testBridgeCredentialStateRenamesBridge() throws {
        var state = BridgeCredentialState(activeBridgeID: "bridge-a", bridges: [
            credential(id: "bridge-a", name: "Local Bridge")
        ])

        try state.rename(id: "bridge-a", name: "Primary")

        XCTAssertEqual(state.activeCredential?.bridgeName, "Primary")
        XCTAssertEqual(state.bridges.first?.directURLs.first?.host, "bridge-a.local")
    }

    func testBridgeCredentialStateNormalizesLegacyBridgeNames() throws {
        let state = BridgeCredentialState(activeBridgeID: "bridge-a", bridges: [
            credential(id: "bridge-a", name: "PopRocket Pi Bridge"),
            credential(id: "bridge-b", name: "PopRocket Bridge")
        ])

        XCTAssertEqual(state.bridges.map(\.bridgeName), ["Local Bridge", "Local Bridge"])
    }

    func testBridgeCredentialStateDropsLegacyDevelopmentBridge() throws {
        let devBridge = PairingCredential(
            bridgeID: "dev",
            bridgeName: "PopRocket Dev Bridge",
            directURLs: [try XCTUnwrap(URL(string: "http://localhost:8080"))],
            relayURL: nil,
            relayWebSocketURL: nil,
            deviceID: "device",
            scopes: ["wol:wake:*"],
            pairedAt: Date(timeIntervalSince1970: 0)
        )
        let realBridge = credential(id: "lab", name: "Lab")

        let state = BridgeCredentialState(activeBridgeID: "dev", bridges: [devBridge, realBridge])

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
