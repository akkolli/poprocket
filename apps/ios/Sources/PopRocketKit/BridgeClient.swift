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
        return try PopRocketCoding.decoder.decode(PairingStartResponse.self, from: data).payload
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
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try Self.validate(response)
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

    public func completeManualPairing(bridgeURL: String, deviceID: String, publicKey: String, scopes: [String]) async throws -> PairingCredential {
        let baseURL = try Self.normalizedBaseURL(from: bridgeURL)
        let payload = try await startPairing(bridgeURL: baseURL.absoluteString)
        return try await completePairing(
            payload: payload,
            deviceID: deviceID,
            publicKey: publicKey,
            scopes: scopes,
            preferredBridgeURL: baseURL
        )
    }

    public func fetchCards(credential: PairingCredential) async throws -> [CardSnapshot] {
        let data = try await firstSuccessfulData(urls: credential.directURLs.map { $0.appending(path: "/v1/cards") })
        return try PopRocketCoding.decoder.decode(CardsResponse.self, from: data).cards
    }

    public func fetchWOLTargets(credential: PairingCredential) async throws -> [WOLTarget] {
        let data = try await firstSuccessfulData(urls: credential.directURLs.map { $0.appending(path: "/v1/wol-targets") })
        return try PopRocketCoding.decoder.decode(WOLTargetsResponse.self, from: data).targets
    }

    public func saveWOLTarget(_ target: WOLTargetRequest, targetID: String?, credential: PairingCredential) async throws -> WOLTarget {
        let body = try PopRocketCoding.encoder.encode(target)
        let path = targetID.map { "/v1/wol-targets/\($0)" } ?? "/v1/wol-targets"
        let method = targetID == nil ? "POST" : "PUT"
        let data = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: path) },
            method: method,
            body: body
        )
        return try PopRocketCoding.decoder.decode(WOLTargetResponse.self, from: data).target
    }

    public func deleteWOLTarget(id: String, credential: PairingCredential) async throws {
        _ = try await firstSuccessfulData(
            urls: credential.directURLs.map { $0.appending(path: "/v1/wol-targets/\(id)") },
            method: "DELETE"
        )
    }

    public func sendAction(_ envelope: ActionEnvelope, credential: PairingCredential) async throws {
        let body = try PopRocketCoding.encoder.encode(envelope)
        let urls = credential.directURLs.map { $0.appending(path: "/v1/actions/\(envelope.actionRunID)") }
        var lastError: Error?
        for url in urls {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = body
                request.timeoutInterval = requestTimeout
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let (_, response) = try await session.data(for: request)
                try Self.validate(response)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func firstSuccessfulData(urls: [URL], method: String = "GET", body: Data? = nil) async throws -> Data {
        var lastError: Error?
        for url in urls {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.httpBody = body
                request.timeoutInterval = requestTimeout
                if body != nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                let (data, response) = try await session.data(for: request)
                try Self.validate(response)
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
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
}
