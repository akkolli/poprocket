import XCTest
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
}
