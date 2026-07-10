import XCTest
@testable import PopRocketKit

final class WOLInputFormatterTests: XCTestCase {
    func testMACNormalizationAcceptsCommonFormats() {
        XCTAssertEqual(WOLInputFormatter.normalizedMACAddress("AA-BB-CC-DD-EE-FF"), "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(WOLInputFormatter.normalizedMACAddress("aabb.ccdd.eeff"), "aa:bb:cc:dd:ee:ff")
        XCTAssertNil(WOLInputFormatter.normalizedMACAddress("not-a-mac"))
    }

    func testIPv4ValidationRejectsAmbiguousOrOutOfRangeValues() {
        XCTAssertTrue(WOLInputFormatter.isValidIPv4Address("192.168.1.25"))
        XCTAssertFalse(WOLInputFormatter.isValidIPv4Address("192.168.001.25"))
        XCTAssertFalse(WOLInputFormatter.isValidIPv4Address("192.168.1.999"))
    }

    func testBroadcastSuggestionUsesTwentyFourBitSubnetDefault() {
        XCTAssertEqual(WOLInputFormatter.suggestedBroadcastIP(from: "192.168.4.25"), "192.168.4.255")
        XCTAssertNil(WOLInputFormatter.suggestedBroadcastIP(from: "server.local"))
    }
}
