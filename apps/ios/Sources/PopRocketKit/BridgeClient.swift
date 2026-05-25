import Foundation

public final class BridgeClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func completePairing(payload: PairingPayload, deviceID: String, publicKey: String, scopes: [String]) async throws -> PairingCredential {
        guard let url = payload.directURLs.first?.appending(path: "/v1/pairing/complete") else {
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try Self.validate(response)
        return PairingCredential(
            bridgeID: payload.bridgeID,
            bridgeName: payload.bridgeName,
            directURLs: payload.directURLs,
            relayURL: payload.relayURL,
            relayWebSocketURL: payload.relayWebSocketURL,
            deviceID: deviceID,
            scopes: scopes,
            pairedAt: Date()
        )
    }

    public func fetchCards(credential: PairingCredential) async throws -> [CardSnapshot] {
        let data = try await firstSuccessfulData(urls: credential.directURLs.map { $0.appending(path: "/v1/cards") })
        return try PopRocketCoding.decoder.decode(CardsResponse.self, from: data).cards
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

    private func firstSuccessfulData(urls: [URL]) async throws -> Data {
        var lastError: Error?
        for url in urls {
            do {
                let (data, response) = try await session.data(from: url)
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
}
