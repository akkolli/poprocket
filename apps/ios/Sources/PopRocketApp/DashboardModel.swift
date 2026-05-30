import CryptoKit
import Foundation
import PopRocketKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CommandShortcut: Codable, Identifiable, Equatable {
    let id: UUID
    var bridgeID: String?
    var name: String
    var command: String
    var lastStatus: String?
    var lastResult: String?
    var lastRunAt: Date?

    init(
        id: UUID,
        bridgeID: String?,
        name: String,
        command: String,
        lastStatus: String? = nil,
        lastResult: String? = nil,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.bridgeID = bridgeID
        self.name = name
        self.command = command
        self.lastStatus = lastStatus
        self.lastResult = lastResult
        self.lastRunAt = lastRunAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, command
        case bridgeID = "bridge_id"
        case lastStatus = "last_status"
        case lastResult = "last_result"
        case lastRunAt = "last_run_at"
    }
}

struct WOLActionState: Equatable {
    var status: String
    var message: String?
    var running: Bool
    var succeeded: Bool
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var cards: [CardSnapshot] = []
    @Published var healthMonitors: [HealthMonitor] = []
    @Published var wolTargets: [WOLTarget] = []
    @Published var auditRecords: [AuditRecord] = []
    @Published var commandShortcuts: [CommandShortcut] = []
    @Published var wakeStates: [String: WOLActionState] = [:]
    @Published var bridgeHealth: BridgeHealth?
    @Published var bridges: [PairingCredential] = []
    @Published var credential: PairingCredential?
    @Published var dashboardStateUpdatedAt: Date?
    @Published var healthMonitorsUpdatedAt: Date?
    @Published var wolTargetsUpdatedAt: Date?
    @Published var bridgeStatusText = "No bridge paired"
    @Published var bridgeReachable = false
    @Published var commandRunning = false
    @Published var runningCommandShortcutID: UUID?
    @Published var commandStatusText: String?
    @Published var commandOutputText: String?
    @Published var commandSucceeded = false
    @Published var statusSnapshotsErrorMessage: String?
    @Published var healthMonitorsErrorMessage: String?
    @Published var wolTargetsErrorMessage: String?
    @Published var activityErrorMessage: String?
    @Published var errorMessage: String?

    private let bridgeStore = BridgeCredentialStore()
    private let cache = AppGroupCache()
    private let client = BridgeClient()
    private let commandShortcutsKey = "poprocket.command.shortcuts.v1"
    private var allCommandShortcuts: [CommandShortcut] = []

    var canRunCommands: Bool {
        commandUnavailableReason == nil
    }

    var bridgeHealthy: Bool {
        bridgeReachable && bridgeHealth?.status == "ok"
    }

    var healthMonitorControlsUnavailableReason: String? {
        guard let credential else {
            return "Pair a bridge before managing monitors."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        if bridgeHealth?.capabilities?.healthMonitors == false {
            return "Health monitors are disabled on this bridge."
        }
        guard Self.scopes(credential.scopes, include: "monitor:read") else {
            return "This pairing does not include monitor:read. Reconnect this bridge in Bridge Settings."
        }
        if let healthMonitorsErrorMessage {
            return healthMonitorsErrorMessage
        }
        guard Self.scopes(credential.scopes, include: "monitor:write") else {
            return "This pairing does not include monitor management. Reconnect this bridge in Bridge Settings."
        }
        return nil
    }

    var wolControlsUnavailableReason: String? {
        guard let credential else {
            return "Pair a bridge before waking devices."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        if bridgeHealth?.capabilities?.wol == false {
            return "Wake-on-LAN is disabled on this bridge."
        }
        guard Self.scopes(credential.scopes, include: "wol:read") else {
            return "This pairing does not include wol:read. Reconnect this bridge in Bridge Settings."
        }
        if let wolTargetsErrorMessage {
            return wolTargetsErrorMessage
        }
        guard Self.canWakeAnyTarget(scopes: credential.scopes) else {
            return "This pairing does not include Wake-on-LAN permission. Reconnect this bridge in Bridge Settings."
        }
        return nil
    }

    var wolTargetManagementUnavailableReason: String? {
        guard let credential else {
            return "Pair a bridge before managing devices."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        if bridgeHealth?.capabilities?.wol == false {
            return "Wake-on-LAN is disabled on this bridge."
        }
        guard Self.scopes(credential.scopes, include: "wol:read") else {
            return "This pairing does not include wol:read. Reconnect this bridge in Bridge Settings."
        }
        guard Self.scopes(credential.scopes, include: "wol:manage") else {
            return "This pairing does not include device management. Reconnect this bridge in Bridge Settings."
        }
        return nil
    }

    func wolWakeUnavailableReason(for target: WOLTarget) -> String? {
        guard let credential else {
            return "Pair a bridge before waking devices."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        if bridgeHealth?.capabilities?.wol == false {
            return "Wake-on-LAN is disabled on this bridge."
        }
        guard Self.scopes(credential.scopes, include: "wol:read") else {
            return "This pairing does not include wol:read. Reconnect this bridge in Bridge Settings."
        }
        if let wolTargetsErrorMessage {
            return wolTargetsErrorMessage
        }
        guard Self.scopes(credential.scopes, include: "wol:wake:\(target.id)") else {
            return "This pairing cannot wake this device. Reconnect this bridge in Bridge Settings."
        }
        return nil
    }

    var commandUnavailableReason: String? {
        guard let credential else {
            return "Pair a bridge before running commands."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        guard Self.scopes(credential.scopes, include: "command:run") else {
            return "This pairing does not include command:run."
        }
        guard let capabilities = bridgeHealth?.capabilities else {
            return nil
        }
        guard capabilities.commandRunnerEnabled else {
            return "Command runner is disabled on this bridge."
        }
        guard capabilities.commandRunnerAdHoc else {
            return "Ad-hoc commands are disabled on this bridge."
        }
        return nil
    }

    func load() async {
        loadCommandShortcuts()
        do {
            applyBridgeState(try bridgeStore.load())
            try await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async throws {
        guard let credential else {
            clearRemoteBridgeState()
            bridgeStatusText = "No bridge paired"
            try? cache.saveCards([])
            return
        }
        bridgeStatusText = "Checking connection"
        bridgeReachable = false
        do {
            let freshBridgeHealth = try await client.fetchBridgeHealth(credential: credential)
            bridgeHealth = freshBridgeHealth
            bridgeStatusText = freshBridgeHealth.status == "ok" ? "Online" : freshBridgeHealth.status
            bridgeReachable = true
            let privateKey = try signingPrivateKey()
            await refreshStatusSnapshots(credential: credential, privateKey: privateKey)
            await refreshHealthMonitors(credential: credential, privateKey: privateKey, capabilities: freshBridgeHealth.capabilities)
            await refreshWOLTargets(credential: credential, privateKey: privateKey, capabilities: freshBridgeHealth.capabilities)
            await refreshActivity(credential: credential, privateKey: privateKey)
        } catch {
            if bridgeReachable, error is BridgeSigningKeyError {
                applyReadAuthenticationError(error)
            } else {
                bridgeStatusText = "Connection failed"
                bridgeReachable = false
                bridgeHealth = nil
                clearSectionErrors()
            }
            throw error
        }
    }

    func refreshFromUser() async {
        do {
            try await refresh()
            errorMessage = nil
        } catch {
            errorMessage = "Could not refresh bridge: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func completePairing(rawPayload: String, displayName: String? = nil) async -> Bool {
        do {
            let payload = try PairingParser.parse(rawPayload)
            let privateKey = try bridgeStore.devicePrivateKey()
            let paired = try await client.completePairing(
                payload: payload,
                deviceID: Self.deviceID(),
                publicKey: ActionSigner.publicKeyBase64(for: privateKey),
                scopes: Self.defaultScopes
            )
            applyBridgeState(try bridgeStore.upsert(Self.namedCredential(paired, displayName: displayName)))
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func completeManualPairing(bridgeURL: String, displayName: String? = nil) async -> Bool {
        do {
            let privateKey = try bridgeStore.devicePrivateKey()
            let paired = try await client.completeManualPairing(
                bridgeURL: bridgeURL,
                deviceID: Self.deviceID(),
                publicKey: ActionSigner.publicKeyBase64(for: privateKey),
                scopes: Self.defaultScopes
            )
            applyBridgeState(try bridgeStore.upsert(Self.namedCredential(paired, displayName: displayName)))
            try await refresh()
            errorMessage = nil
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

    @discardableResult
    func setActiveBridge(_ bridge: PairingCredential) async -> Bool {
        do {
            applyBridgeState(try bridgeStore.setActiveBridge(id: bridge.bridgeID))
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func reconnectBridge(_ bridge: PairingCredential) async -> Bool {
        guard let bridgeURL = bridge.directURLs.first?.absoluteString else {
            errorMessage = "This bridge does not have a direct URL."
            return false
        }
        do {
            let privateKey = try bridgeStore.devicePrivateKey()
            let paired = try await client.completeManualPairing(
                bridgeURL: bridgeURL,
                deviceID: Self.deviceID(),
                publicKey: ActionSigner.publicKeyBase64(for: privateKey),
                scopes: Self.defaultScopes,
                expectedBridgeID: bridge.bridgeID
            )
            let credential = PairingCredential(
                bridgeID: paired.bridgeID,
                bridgeName: bridge.bridgeName,
                directURLs: paired.directURLs,
                relayURL: paired.relayURL,
                relayWebSocketURL: paired.relayWebSocketURL,
                deviceID: paired.deviceID,
                scopes: paired.scopes,
                pairedAt: paired.pairedAt
            )
            applyBridgeState(try bridgeStore.upsert(credential))
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not reconnect \(bridge.bridgeName): \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func removeBridge(_ bridge: PairingCredential) async -> Bool {
        do {
            applyBridgeState(try bridgeStore.removeBridge(id: bridge.bridgeID))
            if credential == nil {
                cards = []
                healthMonitors = []
                wolTargets = []
                auditRecords = []
                commandShortcuts = []
                wakeStates = [:]
                bridgeHealth = nil
                dashboardStateUpdatedAt = nil
                healthMonitorsUpdatedAt = nil
                wolTargetsUpdatedAt = nil
                bridgeStatusText = "No bridge paired"
                bridgeReachable = false
                try? cache.saveCards([])
            } else {
                try await refresh()
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func renameBridge(_ bridge: PairingCredential, name: String) async -> Bool {
        do {
            applyBridgeState(try bridgeStore.renameBridge(id: bridge.bridgeID, name: name))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func runAction(actionID: String, eventID: String?, confirmed: Bool) async {
        do {
            _ = try await NotificationActionRouter().route(
                actionID: actionID,
                eventID: eventID,
                confirmed: confirmed,
                bridgeID: credential?.bridgeID
            )
            try await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runCommand(_ command: String) async {
        await runCommand(command, shortcutID: nil)
    }

    private func runCommand(_ command: String, shortcutID: UUID?) async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard canRunCommands else {
            commandStatusText = "Unavailable"
            commandOutputText = commandUnavailableReason
            commandSucceeded = false
            return
        }
        commandRunning = true
        runningCommandShortcutID = shortcutID
        commandStatusText = "Running"
        commandOutputText = nil
        commandSucceeded = false
        let bridgeID = credential?.bridgeID
        defer {
            commandRunning = false
            runningCommandShortcutID = nil
        }
        do {
            let result = try await NotificationActionRouter().route(
                actionID: "command:run",
                eventID: nil,
                confirmed: true,
                bridgeID: bridgeID,
                parameters: ["command": trimmed]
            )
            let status = result.status ?? "accepted"
            let output = result.resultMessage ?? (result.duplicate == true ? "Duplicate request" : nil)
            let succeeded = Self.actionSucceeded(status: status, duplicate: result.duplicate)
            commandStatusText = status
            commandOutputText = output
            commandSucceeded = succeeded
            recordCommandShortcutRun(shortcutID: shortcutID, status: status, result: output)
            try? await refresh()
            errorMessage = nil
        } catch {
            commandStatusText = "Request failed"
            if let urlError = error as? URLError, urlError.code == .timedOut {
                commandOutputText = "Timed out waiting for the bridge response. The command may still be running on the bridge."
            } else {
                commandOutputText = error.localizedDescription
            }
            commandSucceeded = false
            recordCommandShortcutRun(shortcutID: shortcutID, status: "Request failed", result: commandOutputText)
        }
    }

    func runCommandShortcut(_ shortcut: CommandShortcut) async {
        guard shortcut.bridgeID == credential?.bridgeID else {
            errorMessage = "This command tile belongs to another bridge."
            return
        }
        await runCommand(shortcut.command, shortcutID: shortcut.id)
    }

    func clearCommandResult() {
        guard !commandRunning else { return }
        commandStatusText = nil
        commandOutputText = nil
        commandSucceeded = false
    }

    @discardableResult
    func saveCommandShortcut(name: String, command: String, existingID: UUID?) -> Bool {
        guard let bridgeID = credential?.bridgeID else {
            errorMessage = "Pair a bridge before saving command tiles."
            return false
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name this command tile."
            return false
        }
        guard !trimmedCommand.isEmpty else {
            errorMessage = "Enter a command for this tile."
            return false
        }

        var lastStatus: String?
        var lastResult: String?
        var lastRunAt: Date?
        if let existingID, let index = allCommandShortcuts.firstIndex(where: { $0.id == existingID }) {
            let existing = allCommandShortcuts[index]
            if existing.command == trimmedCommand {
                lastStatus = existing.lastStatus
                lastResult = existing.lastResult
                lastRunAt = existing.lastRunAt
            }
        }

        let shortcut = CommandShortcut(
            id: existingID ?? UUID(),
            bridgeID: bridgeID,
            name: trimmedName,
            command: trimmedCommand,
            lastStatus: lastStatus,
            lastResult: lastResult,
            lastRunAt: lastRunAt
        )
        if let existingID, let index = allCommandShortcuts.firstIndex(where: { $0.id == existingID }) {
            allCommandShortcuts[index] = shortcut
        } else {
            allCommandShortcuts.append(shortcut)
        }
        let saved = persistCommandShortcuts()
        if saved {
            refreshCommandShortcutsForActiveBridge()
            errorMessage = nil
        }
        return saved
    }

    func deleteCommandShortcut(_ shortcut: CommandShortcut) {
        allCommandShortcuts.removeAll { $0.id == shortcut.id }
        if persistCommandShortcuts() {
            refreshCommandShortcutsForActiveBridge()
            errorMessage = nil
        }
    }

    private func recordCommandShortcutRun(shortcutID: UUID?, status: String, result: String?) {
        guard let shortcutID, let index = allCommandShortcuts.firstIndex(where: { $0.id == shortcutID }) else {
            return
        }
        allCommandShortcuts[index].lastStatus = status
        allCommandShortcuts[index].lastResult = result
        allCommandShortcuts[index].lastRunAt = Date()
        if persistCommandShortcuts() {
            refreshCommandShortcutsForActiveBridge()
        }
    }

    func saveHealthMonitor(name: String, kind: String, host: String, port: String, url: String, timeoutSeconds: String, existingID: String?) async -> Bool {
        guard let credential else {
            errorMessage = "Pair a bridge first."
            return false
        }
        let trimmedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTimeout = timeoutSeconds.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = HealthMonitorRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: trimmedKind.isEmpty ? nil : trimmedKind,
            host: Self.nilIfEmpty(host),
            port: trimmedPort.isEmpty ? nil : Int(trimmedPort),
            url: Self.nilIfEmpty(url),
            timeoutSeconds: trimmedTimeout.isEmpty ? nil : Int(trimmedTimeout)
        )
        do {
            let privateKey = try signingPrivateKey()
            _ = try await client.saveHealthMonitor(request, monitorID: existingID, credential: credential, privateKey: privateKey)
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteHealthMonitor(_ monitor: HealthMonitor) async -> Bool {
        guard let credential else {
            errorMessage = "Pair a bridge first."
            return false
        }
        do {
            let privateKey = try signingPrivateKey()
            try await client.deleteHealthMonitor(id: monitor.id, credential: credential, privateKey: privateKey)
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
            let privateKey = try signingPrivateKey()
            _ = try await client.saveWOLTarget(request, targetID: existingID, credential: credential, privateKey: privateKey)
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteWOLTarget(_ target: WOLTarget) async -> Bool {
        guard let credential else {
            errorMessage = "Pair a bridge first."
            return false
        }
        do {
            let privateKey = try signingPrivateKey()
            try await client.deleteWOLTarget(id: target.id, credential: credential, privateKey: privateKey)
            wakeStates[target.id] = nil
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func wake(_ target: WOLTarget) async {
        guard let bridgeID = credential?.bridgeID else {
            wakeStates[target.id] = WOLActionState(
                status: "Unavailable",
                message: "Pair a bridge before waking devices.",
                running: false,
                succeeded: false
            )
            return
        }
        if let reason = wolWakeUnavailableReason(for: target) {
            wakeStates[target.id] = WOLActionState(
                status: "Unavailable",
                message: reason,
                running: false,
                succeeded: false
            )
            return
        }
        wakeStates[target.id] = WOLActionState(
            status: "Running",
            message: nil,
            running: true,
            succeeded: false
        )
        do {
            let result = try await NotificationActionRouter().route(
                actionID: "wol:\(target.id)",
                eventID: nil,
                confirmed: true,
                bridgeID: bridgeID
            )
            let status = result.status ?? (result.duplicate == true ? "accepted" : "completed")
            let succeeded = Self.actionSucceeded(status: status, duplicate: result.duplicate)
            wakeStates[target.id] = WOLActionState(
                status: Self.displayActionStatus(status, duplicate: result.duplicate),
                message: result.resultMessage,
                running: false,
                succeeded: succeeded
            )
            try? await refresh()
            errorMessage = nil
        } catch {
            wakeStates[target.id] = WOLActionState(
                status: "Failed",
                message: error.localizedDescription,
                running: false,
                succeeded: false
            )
        }
    }

    private func applyBridgeState(_ state: BridgeCredentialState) {
        let previousBridgeID = credential?.bridgeID
        bridges = state.bridges
        credential = state.activeCredential
        if previousBridgeID != credential?.bridgeID {
            clearRemoteBridgeState()
            bridgeHealth = nil
            bridgeReachable = false
            wakeStates = [:]
            clearCommandResult()
            try? cache.saveCards([])
            if let credential {
                loadCachedRemoteState(for: credential)
            }
        }
        if credential == nil {
            clearRemoteBridgeState()
            bridgeStatusText = "No bridge paired"
        } else if !bridgeReachable {
            bridgeHealth = nil
            bridgeStatusText = "Paired"
        }
        migrateUnscopedCommandShortcutsIfNeeded()
        refreshCommandShortcutsForActiveBridge()
    }

    private func clearRemoteBridgeState() {
        cards = []
        healthMonitors = []
        wolTargets = []
        auditRecords = []
        commandShortcuts = []
        wakeStates = [:]
        bridgeHealth = nil
        dashboardStateUpdatedAt = nil
        healthMonitorsUpdatedAt = nil
        wolTargetsUpdatedAt = nil
        bridgeReachable = false
        clearSectionErrors()
    }

    private func loadCachedRemoteState(for credential: PairingCredential) {
        guard let cached = try? cache.loadDashboardState(bridgeID: credential.bridgeID) else {
            return
        }
        healthMonitors = cached.healthMonitors
        wolTargets = cached.wolTargets
        dashboardStateUpdatedAt = cached.writtenAt
        healthMonitorsUpdatedAt = cached.healthMonitorsUpdatedAt ?? (cached.healthMonitors.isEmpty ? nil : cached.writtenAt)
        wolTargetsUpdatedAt = cached.wolTargetsUpdatedAt ?? (cached.wolTargets.isEmpty ? nil : cached.writtenAt)
        if !cached.healthMonitors.isEmpty {
            healthMonitorsErrorMessage = nil
        }
        if !cached.wolTargets.isEmpty {
            wolTargetsErrorMessage = nil
        }
    }

    private func saveCachedHealthMonitors(bridgeID: String) {
        healthMonitorsUpdatedAt = Date()
        saveCachedRemoteState(bridgeID: bridgeID)
    }

    private func clearCachedHealthMonitors(bridgeID: String) {
        healthMonitors = []
        healthMonitorsUpdatedAt = nil
        saveCachedRemoteState(bridgeID: bridgeID)
    }

    private func saveCachedWOLTargets(bridgeID: String) {
        wolTargetsUpdatedAt = Date()
        saveCachedRemoteState(bridgeID: bridgeID)
    }

    private func clearCachedWOLTargets(bridgeID: String) {
        wolTargets = []
        wolTargetsUpdatedAt = nil
        saveCachedRemoteState(bridgeID: bridgeID)
    }

    private func saveCachedRemoteState(bridgeID: String) {
        let state = try? cache.saveDashboardState(
            bridgeID: bridgeID,
            healthMonitors: healthMonitors,
            wolTargets: wolTargets,
            healthMonitorsUpdatedAt: healthMonitorsUpdatedAt,
            wolTargetsUpdatedAt: wolTargetsUpdatedAt
        )
        dashboardStateUpdatedAt = state?.writtenAt ?? dashboardStateUpdatedAt
    }

    private func clearSectionErrors() {
        statusSnapshotsErrorMessage = nil
        healthMonitorsErrorMessage = nil
        wolTargetsErrorMessage = nil
        activityErrorMessage = nil
    }

    private func refreshStatusSnapshots(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey) async {
        guard Self.scopes(credential.scopes, include: "cards:read") else {
            cards = []
            statusSnapshotsErrorMessage = Self.missingScopeMessage("cards:read")
            return
        }
        do {
            let freshCards = try await client.fetchCards(credential: credential, privateKey: privateKey)
            cards = freshCards
            statusSnapshotsErrorMessage = nil
            try cache.saveCards(freshCards)
        } catch {
            if Self.isUnsupportedEndpoint(error) {
                cards = []
                statusSnapshotsErrorMessage = nil
            } else {
                statusSnapshotsErrorMessage = Self.sectionError("Could not load status snapshots", error)
            }
        }
    }

    private func refreshHealthMonitors(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey, capabilities: BridgeCapabilities?) async {
        guard capabilities?.healthMonitors != false else {
            clearCachedHealthMonitors(bridgeID: credential.bridgeID)
            healthMonitorsErrorMessage = nil
            return
        }
        guard Self.scopes(credential.scopes, include: "monitor:read") else {
            clearCachedHealthMonitors(bridgeID: credential.bridgeID)
            healthMonitorsErrorMessage = Self.missingScopeMessage("monitor:read")
            return
        }
        do {
            healthMonitors = try await client.fetchHealthMonitors(credential: credential, privateKey: privateKey)
            healthMonitorsErrorMessage = nil
            saveCachedHealthMonitors(bridgeID: credential.bridgeID)
        } catch {
            if capabilities == nil, Self.isUnsupportedEndpoint(error) {
                clearCachedHealthMonitors(bridgeID: credential.bridgeID)
                healthMonitorsErrorMessage = nil
            } else {
                healthMonitorsErrorMessage = Self.sectionError("Could not load monitors", error)
            }
        }
    }

    private func refreshWOLTargets(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey, capabilities: BridgeCapabilities?) async {
        guard capabilities?.wol != false else {
            clearCachedWOLTargets(bridgeID: credential.bridgeID)
            wolTargetsErrorMessage = nil
            return
        }
        guard Self.scopes(credential.scopes, include: "wol:read") else {
            clearCachedWOLTargets(bridgeID: credential.bridgeID)
            wolTargetsErrorMessage = Self.missingScopeMessage("wol:read")
            return
        }
        do {
            wolTargets = try await client.fetchWOLTargets(credential: credential, privateKey: privateKey)
            wolTargetsErrorMessage = nil
            saveCachedWOLTargets(bridgeID: credential.bridgeID)
        } catch {
            if capabilities == nil, Self.isUnsupportedEndpoint(error) {
                clearCachedWOLTargets(bridgeID: credential.bridgeID)
                wolTargetsErrorMessage = nil
            } else {
                wolTargetsErrorMessage = Self.sectionError("Could not load devices", error)
            }
        }
    }

    private func refreshActivity(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey) async {
        guard Self.scopes(credential.scopes, include: "audit:read") else {
            auditRecords = []
            activityErrorMessage = Self.missingScopeMessage("audit:read")
            return
        }
        do {
            auditRecords = try await client.fetchAudit(credential: credential, privateKey: privateKey, limit: 8)
            activityErrorMessage = nil
        } catch {
            if Self.isUnsupportedEndpoint(error) {
                auditRecords = []
                activityErrorMessage = nil
            } else {
                activityErrorMessage = Self.sectionError("Could not load activity", error)
            }
        }
    }

    private func loadCommandShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: commandShortcutsKey) else {
            allCommandShortcuts = []
            commandShortcuts = []
            return
        }
        do {
            allCommandShortcuts = try PopRocketCoding.decoder.decode([CommandShortcut].self, from: data)
            refreshCommandShortcutsForActiveBridge()
        } catch {
            allCommandShortcuts = []
            commandShortcuts = []
            errorMessage = "Could not load saved command tiles."
        }
    }

    private func persistCommandShortcuts() -> Bool {
        do {
            let data = try PopRocketCoding.encoder.encode(allCommandShortcuts)
            UserDefaults.standard.set(data, forKey: commandShortcutsKey)
            return true
        } catch {
            errorMessage = "Could not save command tiles."
            return false
        }
    }

    private func migrateUnscopedCommandShortcutsIfNeeded() {
        guard let bridgeID = credential?.bridgeID else {
            return
        }
        var changed = false
        for index in allCommandShortcuts.indices where allCommandShortcuts[index].bridgeID == nil {
            allCommandShortcuts[index].bridgeID = bridgeID
            changed = true
        }
        if changed {
            _ = persistCommandShortcuts()
        }
    }

    private func refreshCommandShortcutsForActiveBridge() {
        guard let bridgeID = credential?.bridgeID else {
            commandShortcuts = []
            return
        }
        commandShortcuts = allCommandShortcuts.filter { $0.bridgeID == bridgeID }
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

    private static func namedCredential(_ credential: PairingCredential, displayName: String?) -> PairingCredential {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedName, !trimmedName.isEmpty else {
            return credential
        }
        return PairingCredential(
            bridgeID: credential.bridgeID,
            bridgeName: trimmedName,
            directURLs: credential.directURLs,
            relayURL: credential.relayURL,
            relayWebSocketURL: credential.relayWebSocketURL,
            deviceID: credential.deviceID,
            scopes: credential.scopes,
            pairedAt: credential.pairedAt
        )
    }

    private func signingPrivateKey() throws -> Curve25519.Signing.PrivateKey {
        guard let privateKey = try bridgeStore.existingDevicePrivateKey() else {
            throw BridgeSigningKeyError()
        }
        return privateKey
    }

    private func applyReadAuthenticationError(_ error: Error) {
        let message = error.localizedDescription
        cards = []
        healthMonitors = []
        wolTargets = []
        auditRecords = []
        dashboardStateUpdatedAt = nil
        healthMonitorsUpdatedAt = nil
        wolTargetsUpdatedAt = nil
        statusSnapshotsErrorMessage = Self.sectionError("Could not authenticate status snapshots", error)
        healthMonitorsErrorMessage = Self.sectionError("Could not authenticate monitors", error)
        wolTargetsErrorMessage = Self.sectionError("Could not authenticate devices", error)
        activityErrorMessage = Self.sectionError("Could not authenticate activity", error)
        commandStatusText = commandStatusText ?? "Authentication needed"
        commandOutputText = commandOutputText ?? message
    }

    private static func sectionError(_ prefix: String, _ error: Error) -> String {
        "\(prefix): \(error.localizedDescription)"
    }

    private static func missingScopeMessage(_ scope: String) -> String {
        "This pairing does not include \(scope). Reconnect this bridge in Bridge Settings."
    }

    private static func isUnsupportedEndpoint(_ error: Error) -> Bool {
        guard let bridgeError = error as? BridgeHTTPError else {
            return false
        }
        return bridgeError.statusCode == 404
    }

    private static func actionSucceeded(status: String, duplicate: Bool?) -> Bool {
        if duplicate == true {
            return true
        }
        switch status.lowercased() {
        case "completed", "accepted":
            return true
        default:
            return false
        }
    }

    private static func displayActionStatus(_ status: String, duplicate: Bool?) -> String {
        if duplicate == true {
            return "Duplicate"
        }
        switch status.lowercased() {
        case "completed":
            return "Sent"
        case "accepted":
            return "Accepted"
        default:
            return status
        }
    }

    private static func scopes(_ scopes: [String], include required: String) -> Bool {
        if scopes.contains(required) {
            return true
        }
        return scopes.contains { scope in
            guard scope.hasSuffix("*") else {
                return false
            }
            let prefix = String(scope.dropLast())
            return required.hasPrefix(prefix)
        }
    }

    private static func canWakeAnyTarget(scopes: [String]) -> Bool {
        scopes.contains("wol:wake:*") || scopes.contains { $0.hasPrefix("wol:wake:") }
    }

    private static let defaultScopes = [
        "cards:read",
        "audit:read",
        "notify:receive",
        "monitor:read",
        "monitor:write",
        "wol:read",
        "wol:manage",
        "wol:wake:*",
        "command:run"
    ]
}
