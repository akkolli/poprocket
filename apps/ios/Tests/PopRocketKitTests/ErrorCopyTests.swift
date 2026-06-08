import XCTest
@testable import PopRocketKit

final class ErrorCopyTests: XCTestCase {
    func testTimeoutMessageExplainsRecoveryAndUncertainCompletion() {
        let message = PopRocketErrorCopy.operationMessage(URLError(.timedOut))

        XCTAssertTrue(message.contains("Request timed out"))
        XCTAssertTrue(message.contains("retry"))
        XCTAssertTrue(message.contains("may still finish"))
    }

    func testUnreachableBridgeMessageExplainsNetworkAndContainerChecks() {
        let message = PopRocketErrorCopy.operationMessage(URLError(.cannotConnectToHost))

        XCTAssertTrue(message.contains("Bridge is unreachable"))
        XCTAssertTrue(message.contains("Wi-Fi"))
        XCTAssertTrue(message.contains("bridge container"))
    }
}
