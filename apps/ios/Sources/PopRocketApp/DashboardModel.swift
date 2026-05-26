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
    @Published var bridges: [PairingCredential] = []
    @Published var credential: PairingCredential?
    @Published var bridgeStatusText = "No bridge paired"
    @Published var bridgeReachable = false
    @Published var commandRunning = false
    @Published var commandStatusText: String?
    @Published var commandOutputText: String?
    @Published var commandSucceeded = false
    @Published var errorMessage: String?

    private let bridgeStore = BridgeCredentialStore()
    private let cache = AppGroupCache()
    private let client = BridgeClient()

    func load() async {
        do {
            applyBridgeState(try bridgeStore.load())
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async throws {
        guard let credential else {
            cards = []
            wolTargets = []
            bridgeStatusText = "No bridge paired"
            bridgeReachable = false
            try? cache.saveCards([])
            return
        }
        bridgeStatusText = "Checking connection"
        bridgeReachable = false
        do {
            let freshCards = try await client.fetchCards(credential: credential)
            let freshTargets = try await client.fetchWOLTargets(credential: credential)
            cards = freshCards
            wolTargets = freshTargets
            bridgeStatusText = "Connected"
            bridgeReachable = true
            try cache.saveCards(freshCards)
        } catch {
            bridgeStatusText = "Connection failed"
            bridgeReachable = false
            throw error
        }
    }

    @discardableResult
    func completePairing(rawPayload: String) async -> Bool {
        do {
            let payload = try PairingParser.parse(rawPayload)
            let privateKey = try bridgeStore.devicePrivateKey()
            let paired = try await client.completePairing(
                payload: payload,
                deviceID: Self.deviceID(),
                publicKey: ActionSigner.publicKeyBase64(for: privateKey),
                scopes: Self.defaultScopes
            )
            applyBridgeState(try bridgeStore.upsert(paired))
            try await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func completeManualPairing(bridgeURL: String) async -> Bool {
        do {
            let privateKey = try bridgeStore.devicePrivateKey()
            let paired = try await client.completeManualPairing(
                bridgeURL: bridgeURL,
                deviceID: Self.deviceID(),
                publicKey: ActionSigner.publicKeyBase64(for: privateKey),
                scopes: Self.defaultScopes
            )
            applyBridgeState(try bridgeStore.upsert(paired))
            try await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

    func setActiveBridge(_ bridge: PairingCredential) async {
        do {
            applyBridgeState(try bridgeStore.setActiveBridge(id: bridge.bridgeID))
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBridge(_ bridge: PairingCredential) async {
        do {
            applyBridgeState(try bridgeStore.removeBridge(id: bridge.bridgeID))
            if credential == nil {
                cards = []
                wolTargets = []
                bridgeStatusText = "No bridge paired"
                bridgeReachable = false
                try? cache.saveCards([])
            } else {
                try await refresh()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameBridge(_ bridge: PairingCredential, name: String) async -> Bool {
        do {
            applyBridgeState(try bridgeStore.renameBridge(id: bridge.bridgeID, name: name))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func runAction(actionID: String, eventID: String?, confirmed: Bool) async {
        do {
            _ = try await NotificationActionRouter().route(actionID: actionID, eventID: eventID, confirmed: confirmed)
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runCommand(_ command: String) async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commandRunning = true
        commandStatusText = "Running"
        commandOutputText = nil
        commandSucceeded = false
        defer { commandRunning = false }
        do {
            let result = try await NotificationActionRouter().route(
                actionID: "command:run",
                eventID: nil,
                confirmed: true,
                parameters: ["command": trimmed]
            )
            commandStatusText = result.status ?? "accepted"
            commandOutputText = result.resultMessage ?? (result.duplicate == true ? "Duplicate request" : nil)
            commandSucceeded = result.status != "failed"
            try await refresh()
        } catch {
            commandStatusText = "Request failed"
            commandOutputText = error.localizedDescription
            commandSucceeded = false
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

    private func applyBridgeState(_ state: BridgeCredentialState) {
        bridges = state.bridges
        credential = state.activeCredential
        if credential == nil {
            cards = []
            wolTargets = []
            bridgeStatusText = "No bridge paired"
            bridgeReachable = false
        } else if !bridgeReachable {
            bridgeStatusText = "Paired"
        }
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
        "wol:wake:*",
        "command:run"
    ]
}
