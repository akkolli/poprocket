import Foundation
import CryptoKit
import XCTest
@testable import PopRocketKit

final class BridgeClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testStartPairingReportsNonBridgeResponse() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/pairing/start")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            )
            return (try XCTUnwrap(response), Data("<html>not poprocket</html>".utf8))
        }

        let client = BridgeClient(session: Self.session(), requestTimeout: 1)

        do {
            _ = try await client.startPairing(bridgeURL: "http://pluto:6567")
            XCTFail("Expected invalid bridge response error")
        } catch let error as BridgeResponseFormatError {
            XCTAssertEqual(error.endpoint, "/v1/pairing/start")
            XCTAssertTrue(error.localizedDescription.contains("does not look like a PopRocket bridge"))
        }
    }

    func testManualPairingRejectsUnexpectedBridgeIdentityBeforeCompleting() async throws {
        var requestedPaths: [String] = []
        MockURLProtocol.handler = { request in
            requestedPaths.append(request.url?.path ?? "")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/pairing/start")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            let payload = """
            {
              "pairing_token": "token",
              "expires_at": "2026-05-28T12:00:00Z",
              "qr_payload": "poprocket://pair?payload=token",
              "payload": {
                "version": 1,
                "bridge_id": "bridge-other",
                "bridge_name": "Other Bridge",
                "pairing_token": "token",
                "bridge_public_key": "pub",
                "direct_urls": ["http://bridge.local:6567"],
                "expires_at": "2026-05-28T12:00:00Z"
              }
            }
            """
            return (try XCTUnwrap(response), Data(payload.utf8))
        }

        let client = BridgeClient(session: Self.session(), requestTimeout: 1)

        do {
            _ = try await client.completeManualPairing(
                bridgeURL: "http://bridge.local:6567",
                deviceID: "iphone",
                publicKey: "pub",
                scopes: ["cards:read"],
                expectedBridgeID: "bridge-dev"
            )
            XCTFail("Expected bridge identity mismatch")
        } catch let error as BridgeIdentityMismatchError {
            XCTAssertEqual(error.expectedBridgeID, "bridge-dev")
            XCTAssertEqual(error.actualBridgeID, "bridge-other")
            XCTAssertEqual(error.actualBridgeName, "Other Bridge")
            XCTAssertTrue(error.localizedDescription.contains("Add it as a new bridge"))
        }

        XCTAssertEqual(requestedPaths, ["/v1/pairing/start"])
    }

    func testSaveHealthMonitorSendsSignedManagementEnvelope() async throws {
        let privateKey = ActionSigner.makePrivateKey()
        let credential = Self.credential()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/monitors")

            let body = try Self.bodyData(from: request)
            let envelope = try PopRocketCoding.decoder.decode(ActionEnvelope.self, from: body)
            XCTAssertEqual(envelope.actionID, "monitor:create")
            XCTAssertEqual(envelope.actorDeviceID, credential.deviceID)
            XCTAssertEqual(envelope.confirmed, true)
            XCTAssertEqual(envelope.parameters?["name"], "SSH")
            XCTAssertEqual(envelope.parameters?["kind"], "tcp")
            XCTAssertEqual(envelope.parameters?["host"], "pluto")
            XCTAssertEqual(envelope.parameters?["port"], "22")
            XCTAssertTrue(try XCTUnwrap(envelope.parameters?["id"]).hasPrefix("mon_"))

            let signature = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(envelope.signature)))
            XCTAssertTrue(privateKey.publicKey.isValidSignature(signature, for: Data(ActionSigner.canonicalMessage(envelope).utf8)))

            let id = try XCTUnwrap(envelope.parameters?["id"])
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            let payload = """
            {
              "monitor": {
                "id": "\(id)",
                "name": "SSH",
                "kind": "tcp",
                "host": "pluto",
                "port": 22,
                "timeout_seconds": 3,
                "status": "up"
              }
            }
            """
            return (try XCTUnwrap(response), Data(payload.utf8))
        }

        let client = BridgeClient(session: Self.session(), requestTimeout: 1)
        let monitor = try await client.saveHealthMonitor(
            HealthMonitorRequest(name: "SSH", kind: "tcp", host: "pluto", port: 22, url: nil, timeoutSeconds: nil),
            monitorID: nil,
            credential: credential,
            privateKey: privateKey
        )

        XCTAssertEqual(monitor.name, "SSH")
        XCTAssertEqual(monitor.status, "up")
    }

    func testFetchAuditSendsSignedReadHeaders() async throws {
        let privateKey = ActionSigner.makePrivateKey()
        let credential = Self.credential()

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/audit")
            XCTAssertEqual(request.url?.query, "limit=12")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-PopRocket-Device-ID"), credential.deviceID)

            let createdAt = try XCTUnwrap(request.value(forHTTPHeaderField: "X-PopRocket-Created-At"))
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let created = try XCTUnwrap(formatter.date(from: createdAt))
            let rawSignature = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(request.value(forHTTPHeaderField: "X-PopRocket-Signature"))))
            let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
            let signedRequest = BridgeRequestSignature(
                method: "GET",
                path: "/v1/audit",
                query: components?.percentEncodedQuery ?? "",
                actorDeviceID: credential.deviceID,
                createdAt: created
            )
            XCTAssertTrue(privateKey.publicKey.isValidSignature(rawSignature, for: Data(ActionSigner.canonicalMessage(signedRequest).utf8)))

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            return (try XCTUnwrap(response), Data(#"{"actions":[]}"#.utf8))
        }

        let client = BridgeClient(session: Self.session(), requestTimeout: 1)
        let records = try await client.fetchAudit(credential: credential, privateKey: privateKey, limit: 12)

        XCTAssertEqual(records.count, 0)
    }

    func testActionRouterRequiresSigningKeyBeforeSending() async throws {
        let service = "com.poprocket.tests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: service)
        defer {
            try? keychain.delete(account: BridgeCredentialStore.credentialsAccount)
            try? keychain.delete(account: BridgeCredentialStore.legacyActiveAccount)
            try? keychain.delete(account: BridgeCredentialStore.privateKeyAccount)
        }
        let store = BridgeCredentialStore(keychain: keychain)
        try store.save(BridgeCredentialState(activeBridgeID: "bridge-dev", bridges: [Self.credential()]))

        let router = NotificationActionRouter(bridgeClient: BridgeClient(session: Self.session(), requestTimeout: 1), keychain: keychain)

        do {
            _ = try await router.route(actionID: "command:run", eventID: nil, confirmed: true, parameters: ["command": "printf hello"])
            XCTFail("Expected missing signing key error")
        } catch let error as BridgeSigningKeyError {
            XCTAssertTrue(error.localizedDescription.contains("missing its signing key"))
        }
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func credential() -> PairingCredential {
        PairingCredential(
            bridgeID: "bridge-dev",
            bridgeName: "Bridge",
            directURLs: [URL(string: "http://bridge.local:6567")!],
            relayURL: nil,
            relayWebSocketURL: nil,
            deviceID: "iphone",
            scopes: ["cards:read", "audit:read", "monitor:read", "monitor:write", "wol:read", "wol:manage", "wol:wake:*", "command:run"],
            pairedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            throw URLError(.zeroByteResource)
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
