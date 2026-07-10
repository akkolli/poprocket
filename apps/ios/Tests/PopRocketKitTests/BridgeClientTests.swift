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
            _ = try await client.startPairing(bridgeURL: "http://server:6567")
            XCTFail("Expected invalid bridge response error")
        } catch let error as BridgeResponseFormatError {
            XCTAssertEqual(error.endpoint, "/v1/pairing/start")
            XCTAssertTrue(error.localizedDescription.contains("does not look like a PopRocket bridge"))
        }
    }

    func testStartPairingRejectsPlainHTTPOutsideLocalNetwork() async throws {
        MockURLProtocol.handler = { _ in
            XCTFail("An insecure public request should not be sent")
            throw URLError(.badURL)
        }
        let client = BridgeClient(session: Self.session(), requestTimeout: 1)

        do {
            _ = try await client.startPairing(bridgeURL: "http://bridge.example.com:6567")
            XCTFail("Expected transport security error")
        } catch let error as BridgeTransportSecurityError {
            XCTAssertTrue(error.localizedDescription.contains("must use HTTPS"))
        }
    }

    func testEndpointPolicyDoesNotMistakePublicHostnameForIPv6ULA() throws {
        let url = try XCTUnwrap(URL(string: "http://fcorp.example.com:6567"))
        XCTAssertThrowsError(try BridgeEndpointPolicy.validate(url)) { error in
            XCTAssertTrue(error is BridgeTransportSecurityError)
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

    func testManualPairingAllowsLegacyDefaultBridgeIDUpgrade() async throws {
        var requestedPaths: [String] = []
        MockURLProtocol.handler = { request in
            requestedPaths.append(request.url?.path ?? "")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: request.url?.path == "/v1/pairing/start" ? 200 : 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            if request.url?.path == "/v1/pairing/start" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pairing-code")
                let payload = """
                {
                  "pairing_token": "token",
                  "expires_at": "2026-05-28T12:00:00Z",
                  "qr_payload": "poprocket://pair?payload=token",
                  "payload": {
                    "version": 1,
                    "bridge_id": "bridge-pluto",
                    "bridge_name": "Local Bridge",
                    "pairing_token": "token",
                    "bridge_public_key": "pub",
                    "direct_urls": ["http://bridge.local:6567"],
                    "expires_at": "2026-05-28T12:00:00Z"
                  }
                }
                """
                return (try XCTUnwrap(response), Data(payload.utf8))
            }
            let completed = #"{"device_id":"iphone","scopes":["cards:read"],"pairing_access_token":"pairing-code","relay_access_token":"relay-token"}"#
            return (try XCTUnwrap(response), Data(completed.utf8))
        }

        let client = BridgeClient(session: Self.session(), requestTimeout: 1)
        let credential = try await client.completeManualPairing(
            bridgeURL: "http://bridge.local:6567",
            deviceID: "iphone",
            publicKey: "pub",
            scopes: ["cards:read"],
            pairingAccessToken: "pairing-code",
            expectedBridgeID: BridgeNaming.legacyDefaultBridgeID
        )

        XCTAssertEqual(credential.bridgeID, "bridge-pluto")
        XCTAssertEqual(credential.bridgeName, "Local Bridge")
        XCTAssertEqual(credential.scopes, ["cards:read"])
        XCTAssertEqual(credential.pairingAccessToken, "pairing-code")
        XCTAssertEqual(credential.relayAccessToken, "relay-token")
        XCTAssertEqual(requestedPaths, ["/v1/pairing/start", "/v1/pairing/complete"])
    }

    func testFetchBridgeHealthNormalizesLegacyBridgeName() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/health")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            let payload = """
            {
              "status": "ok",
              "bridge_id": "poprocket-pi",
              "bridge_name": "PopRocket Pi Bridge",
              "started_at": "2026-05-28T12:00:00Z",
              "server_time": "2026-05-28T12:00:30Z",
              "uptime_seconds": 30
            }
            """
            return (try XCTUnwrap(response), Data(payload.utf8))
        }

        let client = BridgeClient(session: Self.session(), requestTimeout: 1)
        let health = try await client.fetchBridgeHealth(credential: Self.credential())

        XCTAssertEqual(health.bridgeID, "poprocket-pi")
        XCTAssertEqual(health.bridgeName, "Local Bridge")
    }

    func testBridgeClientRejectsOversizedResponseBeforeDecode() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            return (try XCTUnwrap(response), Data(repeating: 0x61, count: (4 << 20) + 1))
        }
        let client = BridgeClient(session: Self.session(), requestTimeout: 1)

        do {
            _ = try await client.fetchBridgeHealth(credential: Self.credential())
            XCTFail("Expected oversized response error")
        } catch let error as BridgeResponseTooLargeError {
            XCTAssertEqual(error.limit, 4 << 20)
        }
    }

    func testRegisterDeviceForNotificationsPostsRelayRegistration() async throws {
        let credential = Self.credential(
            relayURL: URL(string: "http://relay.local:6568")
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "http://relay.local:6568/v1/devices/register")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer relay-token")

            let body = try JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: String]
            XCTAssertEqual(body?["bridge_id"], credential.bridgeID)
            XCTAssertEqual(body?["device_id"], credential.deviceID)
            XCTAssertEqual(body?["platform"], "ios")
            XCTAssertEqual(body?["apns_token"], "apns-token")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            let payload = """
            {
              "bridge_id": "\(credential.bridgeID)",
              "device_id": "\(credential.deviceID)",
              "platform": "ios",
              "apns_token": "apns-token",
              "registered_at": "2026-06-14T12:00:00Z"
            }
            """
            return (try XCTUnwrap(response), Data(payload.utf8))
        }

        let client = BridgeClient(session: Self.session(), requestTimeout: 1)
        let registered = try await client.registerDeviceForNotifications(
            apnsToken: "apns-token",
            platform: "ios",
            credential: credential
        )

        XCTAssertEqual(registered.bridgeID, credential.bridgeID)
        XCTAssertEqual(registered.deviceID, credential.deviceID)
        XCTAssertEqual(registered.apnsToken, "apns-token")
    }

    func testSendActionFallsBackToRelayWhenDirectBridgeIsUnreachable() async throws {
        let credential = Self.credential(
            relayURL: URL(string: "http://relay.local:6568")
        )
        let envelope = ActionEnvelope(
            actionRunID: "run_watch_wake",
            eventID: nil,
            actionID: "wol:desktop",
            actorDeviceID: credential.deviceID,
            idempotencyKey: nil,
            confirmed: true
        )

        MockURLProtocol.handler = { request in
            if request.url?.host == "bridge.local" {
                throw URLError(.cannotConnectToHost)
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "http://relay.local:6568/v1/actions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer relay-token")
            let relayRequest = try PopRocketCoding.decoder.decode(RelayActionRequest.self, from: Self.bodyData(from: request))
            XCTAssertEqual(relayRequest.bridgeID, credential.bridgeID)
            XCTAssertEqual(relayRequest.actionRunID, envelope.actionRunID)
            XCTAssertEqual(relayRequest.deviceID, credential.deviceID)
            XCTAssertEqual(relayRequest.payload.actionID, "wol:desktop")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 202,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
            return (try XCTUnwrap(response), Data(#"{"bridge_id":"bridge-dev","action_run_id":"run_watch_wake","status":"queued"}"#.utf8))
        }

        let client = BridgeClient(session: Self.session(), requestTimeout: 1)
        let result = try await client.sendAction(envelope, credential: credential)

        XCTAssertEqual(result.actionRunID, "run_watch_wake")
        XCTAssertEqual(result.status, "queued")
        XCTAssertTrue(ActionRunOutcome.succeeded(status: "queued", duplicate: nil))
        XCTAssertEqual(ActionRunOutcome.displayStatus(status: "queued", duplicate: nil), "Queued")
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
            XCTAssertEqual(envelope.parameters?["host"], "server")
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
                "host": "server",
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
            HealthMonitorRequest(name: "SSH", kind: "tcp", host: "server", port: 22, url: nil, timeoutSeconds: nil),
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
        let router = NotificationActionRouter(
            bridgeClient: BridgeClient(session: Self.session(), requestTimeout: 1),
            bridgeStore: MissingSigningKeyCredentialProvider(credential: Self.credential())
        )

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

    private static func credential(relayURL: URL? = nil) -> PairingCredential {
        PairingCredential(
            bridgeID: "bridge-dev",
            bridgeName: "Bridge",
            directURLs: [URL(string: "http://bridge.local:6567")!],
            relayURL: relayURL,
            relayWebSocketURL: nil,
            relayAccessToken: relayURL == nil ? nil : "relay-token",
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

private struct MissingSigningKeyCredentialProvider: BridgeCredentialProviding {
    let credential: PairingCredential

    func credential(id bridgeID: String?) throws -> PairingCredential? {
        credential
    }

    func existingDevicePrivateKey() throws -> Curve25519.Signing.PrivateKey? {
        nil
    }
}
