import Foundation
import PopRocketKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class DashboardModel: ObservableObject {
    @Published var cards: [CardSnapshot] = []
    @Published var wolTargets: [WOLTarget] = []
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
        let freshTargets = try await client.fetchWOLTargets(credential: credential)
        cards = freshCards
        wolTargets = freshTargets
        try cache.saveCards(freshCards)
    }

    func completePairing(rawPayload: String) async {
        do {
            let payload = try PairingParser.parse(rawPayload)
            let privateKey = ActionSigner.makePrivateKey()
            try keychain.save(privateKey.rawRepresentation, account: "device_private_key")
            let paired = try await client.completePairing(
                payload: payload,
                deviceID: Self.deviceID(),
                publicKey: ActionSigner.publicKeyBase64(for: privateKey),
                scopes: Self.defaultScopes
            )
            try keychain.save(paired, account: "active_pairing")
            credential = paired
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeManualPairing(bridgeURL: String) async {
        do {
            let privateKey = ActionSigner.makePrivateKey()
            try keychain.save(privateKey.rawRepresentation, account: "device_private_key")
            let paired = try await client.completeManualPairing(
                bridgeURL: bridgeURL,
                deviceID: Self.deviceID(),
                publicKey: ActionSigner.publicKeyBase64(for: privateKey),
                scopes: Self.defaultScopes
            )
            try keychain.save(paired, account: "active_pairing")
            credential = paired
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handle(_ url: URL) async {
        guard
            url.scheme == "poprocket",
            url.host == "pair" || url.path == "/pair",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value,
            !payload.isEmpty
        else {
            return
        }
        await completePairing(rawPayload: payload)
    }

    func runAction(actionID: String, eventID: String?, confirmed: Bool) async {
        do {
            try await NotificationActionRouter().route(actionID: actionID, eventID: eventID, confirmed: confirmed)
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveWOLTarget(name: String, mac: String, ipAddress: String, broadcastIP: String, udpPort: String, existingID: String?) async -> Bool {
        guard let credential else {
            errorMessage = "Pair a bridge first."
            return false
        }
        do {
            let trimmedPort = udpPort.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedPort = trimmedPort.isEmpty ? nil : Int(trimmedPort)
            let request = WOLTargetRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                mac: mac.trimmingCharacters(in: .whitespacesAndNewlines),
                ipAddress: Self.nilIfEmpty(ipAddress),
                broadcastIP: Self.nilIfEmpty(broadcastIP),
                udpPort: parsedPort
            )
            _ = try await client.saveWOLTarget(request, targetID: existingID, credential: credential)
            try await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteWOLTarget(_ target: WOLTarget) async {
        guard let credential else { return }
        do {
            try await client.deleteWOLTarget(id: target.id, credential: credential)
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func wake(_ target: WOLTarget) async {
        await runAction(actionID: "wol:\(target.id)", eventID: nil, confirmed: true)
    }

    private static func deviceID() -> String {
        #if canImport(UIKit)
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        Host.current().localizedName ?? UUID().uuidString
        #endif
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let defaultScopes = [
        "cards:read",
        "audit:read",
        "notify:receive",
        "wol:wake:*"
    ]
}
