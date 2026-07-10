import XCTest
@testable import PopRocketKit

final class PairingURLFormatterTests: XCTestCase {
    func testAddsDefaultSchemeForLocalBridge() {
        XCTAssertEqual(PairingURLFormatter.normalizedDisplayURL("bridge.local:6567"), "http://bridge.local:6567")
        XCTAssertEqual(PairingURLFormatter.normalizedDisplayURL("192.168.1.25:6567/"), "http://192.168.1.25:6567")
    }

    func testRejectsCredentialsAndPublicPlainHTTP() {
        XCTAssertNil(PairingURLFormatter.normalizedDisplayURL("http://user:secret@bridge.local:6567"))
        XCTAssertNil(PairingURLFormatter.normalizedDisplayURL("http://bridge.example.com:6567"))
        XCTAssertNotNil(PairingURLFormatter.normalizedDisplayURL("https://bridge.example.com"))
    }

    func testValidationExplainsMissingAndUnsafeValues() {
        XCTAssertEqual(PairingURLFormatter.validationMessage(for: ""), "Enter a bridge URL.")
        XCTAssertEqual(
            PairingURLFormatter.validationMessage(for: "http://bridge.example.com"),
            "Enter a local HTTP address or an HTTPS bridge URL."
        )
    }
}
