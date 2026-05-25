import Foundation
import PopRocketKit
import SwiftUI
import UIKit

@MainActor
final class DashboardModel: ObservableObject {
    @Published var cards: [CardSnapshot] = []
    @Published var credential: PairingCredential?
    @Published var errorMessage: String?

    private let keychain = KeychainStore()
    private let cache = AppGroupCache()
    private let client = BridgeClient()

    func load() async {
        do {
            credential = try keychain.load(PairingCredential.self, account: "active_pairing")
            if let cached = try cache.loadCards() {
                cards = cached.cards
            }
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async throws {
        guard let credential else { return }
        let freshCards = try await client.fetchCards(credential: credential)
        cards = freshCards
        try cache.saveCards(freshCards)
    }

    func completePairing(rawPayload: String) async {
        do {
            let payload = try PairingParser.parse(rawPayload)
            let privateKey = ActionSigner.makePrivateKey()
            try keychain.save(privateKey.rawRepresentation, account: "device_private_key")
            let scopes = [
                "cards:read",
                "audit:read",
                "notify:receive",
                "wol:wake:nas01"
            ]
            let paired = try await client.completePairing(
                payload: payload,
                deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                publicKey: ActionSigner.publicKeyBase64(for: privateKey),
                scopes: scopes
            )
            try keychain.save(paired, account: "active_pairing")
            credential = paired
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
