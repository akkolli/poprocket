import CryptoKit
import Foundation

public final class BridgeClient {
    private let session: URLSession
    private let requestTimeout: TimeInterval

    public convenience init() {
        self.init(session: .shared, requestTimeout: 8)
    }

    public convenience init(session: URLSession) {
        self.init(session: session, requestTimeout: 8)
    }

    public init(session: URLSession, requestTimeout: TimeInterval) {
        self.session = session
        self.requestTimeout = requestTimeout
    }

    public func startPairing(bridgeURL: String) async throws -> PairingPayload {
        let baseURL = try Self.normalizedBaseURL(from: bridgeURL)
        let data = try await firstSuccessfulData(urls: [baseURL.appending(path: "/v1/pairing/start")], method: "POST")
        return try Self.decode(PairingStartResponse.self, from: data, endpoint: "/v1/pairing/start").payload
    }

    public func completePairing(payload: PairingPayload, deviceID: String, publicKey: String, scopes: [String], preferredBridgeURL: URL? = nil) async throws -> PairingCredential {
        let directURLs = Self.mergedDirectURLs(preferredBridgeURL: preferredBridgeURL, payloadURLs: payload.directURLs)
        guard let url = directURLs.first?.appending(path: "/v1/pairing/complete") else {
            throw URLError(.badURL)
        }
        let body: [String: Any] = [
            "pairing_token": payload.pairingToken,
            "device_id": deviceID,
            "public_key": publicKey,
            "scopes": scopes
        ]
        let requestData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await session.data(for: request)
        try Self.validate(response, data: responseData)
        return PairingCredential(
            bridgeID: payload.bridgeID,
            bridgeName: payload.bridgeName,
            directURLs: directURLs,
            relayURL: payload.relayURL,
            relayWebSocketURL: payload.relayWebSocketURL,
            deviceID: deviceID,
            scopes: scopes,
            pairedAt: Date()
        )
    }

    public func completeManualPairing(
        bridgeURL: String,
        deviceID: String,
        publicKey: String,
        scopes: [String],
        expectedBridgeID: String? = nil
    ) async throws -> PairingCredential {
        let baseURL = try Self.normalizedBaseURL(from: bridgeURL)
        let payload = try await startPairing(bridgeURL: baseURL.absoluteString)
        if let expectedBridgeID, payload.bridgeID != expectedBridgeID {
            throw BridgeIdentityMismatchError(
                expectedBridgeID: expectedBridgeID,
                actualBridgeID: payload.bridgeID,
                actualBridgeName: payload.bridgeName
            )
        }
        return try await completePairing(
            payload: payload,
            deviceID: deviceID,
            publicKey: publicKey,
            scopes: scopes,
            preferredBridgeURL: baseURL
        )
    }

    public func fetchBridgeHealth(credential: PairingCredential) async throws -> BridgeHealth {
        let data = try await firstSuccessfulData(urls: credential.directURLs.map { $0.appending(path: "/v1/health") })
        return try Self.decode(BridgeHealth.self, from: data, endpoint: "/v1/health")
    }

    public func fetchCards(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey) async throws -> [CardSnapshot] {
        let data = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: "/v1/cards") },
            credential: credential,
            privateKey: privateKey
        )
        return try Self.decode(CardsResponse.self, from: data, endpoint: "/v1/cards").cards
    }

    public func fetchWOLTargets(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey) async throws -> [WOLTarget] {
        let data = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: "/v1/wol-targets") },
            credential: credential,
            privateKey: privateKey
        )
        return try Self.decode(WOLTargetsResponse.self, from: data, endpoint: "/v1/wol-targets").targets
    }

    public func fetchHealthMonitors(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey) async throws -> [HealthMonitor] {
        let data = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: "/v1/monitors") },
            credential: credential,
            privateKey: privateKey
        )
        return try Self.decode(HealthMonitorsResponse.self, from: data, endpoint: "/v1/monitors").monitors
    }

    public func fetchAudit(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey, limit: Int = 8) async throws -> [AuditRecord] {
        let urls = credential.directURLs.compactMap { baseURL -> URL? in
            var components = URLComponents(url: baseURL.appending(path: "/v1/audit"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
            return components?.url
        }
        let data = try await firstSuccessfulData(urls: urls, credential: credential, privateKey: privateKey)
        return try Self.decode(AuditResponse.self, from: data, endpoint: "/v1/audit").actions
    }

    public func saveHealthMonitor(
        _ monitor: HealthMonitorRequest,
        monitorID: String?,
        credential: PairingCredential,
        privateKey: Curve25519.Signing.PrivateKey
    ) async throws -> HealthMonitor {
        let id = monitorID ?? monitor.id ?? Self.generatedID(prefix: "mon")
        let signedMonitor = HealthMonitorRequest(
            id: id,
            name: monitor.name,
            kind: monitor.kind,
            host: monitor.host,
            port: monitor.port,
            url: monitor.url,
            timeoutSeconds: monitor.timeoutSeconds
        )
        let path = monitorID.map { "/v1/monitors/\($0)" } ?? "/v1/monitors"
        let method = monitorID == nil ? "POST" : "PUT"
        let actionID = monitorID == nil ? "monitor:create" : "monitor:update"
        let body = try signedMutationBody(
            actionID: actionID,
            credential: credential,
            parameters: Self.parameters(from: signedMonitor),
            privateKey: privateKey
        )
        let data = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: path) },
            method: method,
            body: body
        )
        return try Self.decode(HealthMonitorResponse.self, from: data, endpoint: path).monitor
    }

    public func deleteHealthMonitor(id: String, credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey) async throws {
        let body = try signedMutationBody(
            actionID: "monitor:delete",
            credential: credential,
            parameters: ["id": id],
            privateKey: privateKey
        )
        _ = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: "/v1/monitors/\(id)") },
            method: "DELETE",
            body: body
        )
    }

    public func saveWOLTarget(
        _ target: WOLTargetRequest,
        targetID: String?,
        credential: PairingCredential,
        privateKey: Curve25519.Signing.PrivateKey
    ) async throws -> WOLTarget {
        let id = targetID ?? target.id ?? Self.generatedID(prefix: "wol")
        let signedTarget = WOLTargetRequest(
            id: id,
            name: target.name,
            mac: target.mac,
            ipAddress: target.ipAddress,
            broadcastIP: target.broadcastIP,
            udpPort: target.udpPort
        )
        let path = targetID.map { "/v1/wol-targets/\($0)" } ?? "/v1/wol-targets"
        let method = targetID == nil ? "POST" : "PUT"
        let actionID = targetID == nil ? "wol-target:create" : "wol-target:update"
        let body = try signedMutationBody(
            actionID: actionID,
            credential: credential,
            parameters: Self.parameters(from: signedTarget),
            privateKey: privateKey
        )
        let data = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: path) },
            method: method,
            body: body
        )
        return try Self.decode(WOLTargetResponse.self, from: data, endpoint: path).target
    }

    public func deleteWOLTarget(id: String, credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey) async throws {
        let body = try signedMutationBody(
            actionID: "wol-target:delete",
            credential: credential,
            parameters: ["id": id],
            privateKey: privateKey
        )
        _ = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: "/v1/wol-targets/\(id)") },
            method: "DELETE",
            body: body
        )
    }

    public func sendAction(_ envelope: ActionEnvelope, credential: PairingCredential) async throws -> ActionResult {
        let body = try PopRocketCoding.encoder.encode(envelope)
        let urls = credential.directURLs.map { $0.appending(path: "/v1/actions/\(envelope.actionRunID)") }
        var lastError: Error?
        for url in urls {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = body
                request.timeoutInterval = max(requestTimeout, 40)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let (data, response) = try await session.data(for: request)
                try Self.validate(response, data: data)
                return try Self.decode(ActionResult.self, from: data, endpoint: "/v1/actions")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func firstSuccessfulData(
        urls: [URL],
        method: String = "GET",
        body: Data? = nil,
        credential: PairingCredential? = nil,
        privateKey: Curve25519.Signing.PrivateKey? = nil
    ) async throws -> Data {
        var lastError: Error?
        for url in urls {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.httpBody = body
                request.timeoutInterval = requestTimeout
                if let credential, let privateKey {
                    try Self.sign(&request, method: method, credential: credential, privateKey: privateKey)
                }
                if body != nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                let (data, response) = try await session.data(for: request)
                try Self.validate(response, data: data)
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func signedMutationBody(
        actionID: String,
        credential: PairingCredential,
        parameters: [String: String],
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> Data {
        var envelope = ActionEnvelope(
            actionRunID: "run_\(UUID().uuidString.lowercased())",
            eventID: nil,
            actionID: actionID,
            actorDeviceID: credential.deviceID,
            idempotencyKey: nil,
            confirmed: true,
            parameters: parameters
        )
        try ActionSigner.sign(&envelope, privateKey: privateKey)
        return try PopRocketCoding.encoder.encode(envelope)
    }

    private static func sign(
        _ request: inout URLRequest,
        method: String,
        credential: PairingCredential,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var signature = BridgeRequestSignature(
            method: method,
            path: url.path,
            query: components?.percentEncodedQuery ?? "",
            actorDeviceID: credential.deviceID
        )
        try ActionSigner.sign(&signature, privateKey: privateKey)
        request.setValue(signature.actorDeviceID, forHTTPHeaderField: "X-PopRocket-Device-ID")
        request.setValue(RFC3339.string(from: signature.createdAt), forHTTPHeaderField: "X-PopRocket-Created-At")
        request.setValue(signature.signature, forHTTPHeaderField: "X-PopRocket-Signature")
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? PopRocketCoding.decoder.decode(BridgeErrorResponse.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw BridgeHTTPError(statusCode: http.statusCode, message: message)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try PopRocketCoding.decoder.decode(type, from: data)
        } catch is DecodingError {
            throw BridgeResponseFormatError(endpoint: endpoint)
        }
    }

    private static func normalizedBaseURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: withScheme), components.host != nil else {
            throw URLError(.badURL)
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private static func mergedDirectURLs(preferredBridgeURL: URL?, payloadURLs: [URL]) -> [URL] {
        var urls: [URL] = []
        if let preferredBridgeURL {
            urls.append(preferredBridgeURL)
        }
        urls.append(contentsOf: payloadURLs)

        var seen: Set<String> = []
        return urls.filter { url in
            let key = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private static func generatedID(prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    private static func parameters(from monitor: HealthMonitorRequest) -> [String: String] {
        var parameters: [String: String] = [:]
        parameters["id"] = monitor.id
        parameters["name"] = monitor.name
        parameters["kind"] = monitor.kind
        parameters["host"] = monitor.host
        parameters["url"] = monitor.url
        if let port = monitor.port {
            parameters["port"] = String(port)
        }
        if let timeoutSeconds = monitor.timeoutSeconds {
            parameters["timeout_seconds"] = String(timeoutSeconds)
        }
        return parameters.compactMapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func parameters(from target: WOLTargetRequest) -> [String: String] {
        var parameters: [String: String] = [:]
        parameters["id"] = target.id
        parameters["name"] = target.name
        parameters["mac"] = target.mac
        parameters["ip_address"] = target.ipAddress
        parameters["broadcast_ip"] = target.broadcastIP
        if let udpPort = target.udpPort {
            parameters["udp_port"] = String(udpPort)
        }
        return parameters.compactMapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

public struct BridgeHTTPError: Error, LocalizedError, Equatable {
    public let statusCode: Int
    public let message: String

    public var errorDescription: String? {
        "Bridge returned \(statusCode): \(message)"
    }
}

public struct BridgeResponseFormatError: Error, LocalizedError, Equatable {
    public let endpoint: String

    public var errorDescription: String? {
        "This URL responded, but it does not look like a PopRocket bridge (\(endpoint)). Check the host and port."
    }
}

public struct BridgeIdentityMismatchError: Error, LocalizedError, Equatable {
    public let expectedBridgeID: String
    public let actualBridgeID: String
    public let actualBridgeName: String

    public var errorDescription: String? {
        "This URL belongs to \(actualBridgeName) (\(actualBridgeID)), not the selected bridge (\(expectedBridgeID)). Add it as a new bridge instead."
    }
}

private struct BridgeErrorResponse: Codable {
    let error: String
}
