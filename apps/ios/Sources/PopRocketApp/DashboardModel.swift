import CryptoKit
import Foundation
import PopRocketKit
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct WOLActionState: Equatable {
    var status: String
    var message: String?
    var running: Bool
    var succeeded: Bool
    var bridgeName: String?
    var updatedAt: Date?
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var cards: [CardSnapshot] = []
    @Published var healthMonitors: [HealthMonitor] = []
    @Published var wolTargets: [WOLTarget] = []
    @Published var auditRecords: [AuditRecord] = []
    @Published var commandShortcuts: [CommandShortcut] = []
    @Published var widgetActionSelections: [WidgetActionSelection] = []
    @Published var wakeStates: [String: WOLActionState] = [:]
    @Published var bridgeHealth: BridgeHealth?
    @Published var bridges: [PairingCredential] = []
    @Published var credential: PairingCredential?
    @Published var dashboardStateUpdatedAt: Date?
    @Published var healthMonitorsUpdatedAt: Date?
    @Published var wolTargetsUpdatedAt: Date?
    @Published var bridgeStatusText = "No bridge"
    @Published var bridgeReachable = false
    @Published var commandRunning = false
    @Published var runningCommandShortcutID: UUID?
    @Published var commandStatusText: String?
    @Published var commandOutputText: String?
    @Published var commandSucceeded = false
    @Published var commandResultTitle: String?
    @Published var commandResultCommand: String?
    @Published var commandResultBridgeName: String?
    @Published var commandResultUpdatedAt: Date?
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
    private var allWidgetActionSelections: [WidgetActionSelection] = []

    var canRunCommands: Bool {
        commandUnavailableReason == nil
    }

    var bridgeHealthy: Bool {
        bridgeReachable && bridgeHealth?.status == "ok"
    }

    var healthMonitorControlsUnavailableReason: String? {
        guard let credential else {
            return "Add a bridge before managing monitors."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        if bridgeHealth?.capabilities?.healthMonitors == false {
            return "Health monitors are disabled on this bridge."
        }
        guard Self.scopes(credential.scopes, include: "monitor:read") else {
            return Self.missingScopeMessage("monitor:read")
        }
        if let healthMonitorsErrorMessage {
            return healthMonitorsErrorMessage
        }
        guard Self.scopes(credential.scopes, include: "monitor:write") else {
            return Self.missingScopeMessage("monitor:write")
        }
        return nil
    }

    var wolControlsUnavailableReason: String? {
        guard let credential else {
            return "Add a bridge before waking devices."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        if bridgeHealth?.capabilities?.wol == false {
            return "Wake-on-LAN is disabled on this bridge."
        }
        guard Self.scopes(credential.scopes, include: "wol:read") else {
            return Self.missingScopeMessage("wol:read")
        }
        if let wolTargetsErrorMessage {
            return wolTargetsErrorMessage
        }
        guard Self.canWakeAnyTarget(scopes: credential.scopes) else {
            return "This bridge cannot wake devices. Reconnect it in Settings."
        }
        return nil
    }

    var wolTargetManagementUnavailableReason: String? {
        guard let credential else {
            return "Add a bridge before managing devices."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        if bridgeHealth?.capabilities?.wol == false {
            return "Wake-on-LAN is disabled on this bridge."
        }
        guard Self.scopes(credential.scopes, include: "wol:read") else {
            return Self.missingScopeMessage("wol:read")
        }
        guard Self.scopes(credential.scopes, include: "wol:manage") else {
            return Self.missingScopeMessage("wol:manage")
        }
        return nil
    }

    func wolWakeUnavailableReason(for target: WOLTarget) -> String? {
        guard let credential else {
            return "Add a bridge before waking devices."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        if bridgeHealth?.capabilities?.wol == false {
            return "Wake-on-LAN is disabled on this bridge."
        }
        guard Self.scopes(credential.scopes, include: "wol:read") else {
            return Self.missingScopeMessage("wol:read")
        }
        if let wolTargetsErrorMessage {
            return wolTargetsErrorMessage
        }
        guard Self.scopes(credential.scopes, include: "wol:wake:\(target.id)") else {
            return "This bridge cannot wake this device. Reconnect it in Settings."
        }
        return nil
    }

    var commandUnavailableReason: String? {
        guard let credential else {
            return "Add a bridge before running commands."
        }
        guard bridgeReachable else {
            return bridgeStatusText == "Checking connection" ? "Checking bridge connection." : "Bridge is offline."
        }
        guard Self.scopes(credential.scopes, include: "command:run") else {
            return Self.missingScopeMessage("command:run")
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
        loadWidgetActionSelections()
        loadCommandShortcuts()
        do {
            applyBridgeState(try bridgeStore.load())
        } catch {
            errorMessage = "Could not load bridge settings: \(PopRocketErrorCopy.operationMessage(error))"
            return
        }
        do {
            try await refresh()
            errorMessage = nil
        } catch {
            // Automatic launch refresh failures are already reflected in the bridge and section state.
            errorMessage = nil
        }
    }

    func refresh() async throws {
        guard let credential else {
            clearRemoteBridgeState()
            bridgeStatusText = "No bridge"
            try? cache.saveCards([])
            try? cache.clearActiveDashboardState()
            reloadWidgets()
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
            reloadWidgets()
        } catch {
            if bridgeReachable, error is BridgeSigningKeyError {
                applyReadAuthenticationError(error)
            } else {
                bridgeStatusText = "Connection failed"
                bridgeReachable = false
                bridgeHealth = nil
                clearSectionErrors()
                saveActiveBridgeConnectionState(bridgeReachable: false, bridgeStatus: bridgeStatusText)
                reloadWidgets()
            }
            throw error
        }
    }

    func refreshFromUser() async {
        do {
            try await refresh()
            errorMessage = nil
        } catch {
            errorMessage = "Could not refresh bridge: \(PopRocketErrorCopy.operationMessage(error))"
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
            errorMessage = PopRocketErrorCopy.operationMessage(error)
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
            errorMessage = PopRocketErrorCopy.operationMessage(error)
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
            errorMessage = PopRocketErrorCopy.operationMessage(error)
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
            applyBridgeState(try bridgeStore.replaceBridge(id: bridge.bridgeID, with: credential))
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not reconnect \(bridge.bridgeName): \(PopRocketErrorCopy.operationMessage(error))"
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
                bridgeStatusText = "No bridge"
                bridgeReachable = false
                try? cache.saveCards([])
                try? cache.clearActiveDashboardState()
                reloadWidgets()
            } else {
                try await refresh()
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = PopRocketErrorCopy.operationMessage(error)
            return false
        }
    }

    func renameBridge(_ bridge: PairingCredential, name: String) async -> Bool {
        do {
            let state = try bridgeStore.renameBridge(id: bridge.bridgeID, name: name)
            applyBridgeState(state)
            if state.activeCredential?.bridgeID == bridge.bridgeID {
                updateCachedBridgeName(
                    bridgeID: bridge.bridgeID,
                    bridgeName: state.activeCredential?.bridgeName
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = PopRocketErrorCopy.operationMessage(error)
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
            errorMessage = PopRocketErrorCopy.operationMessage(error)
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
            commandResultTitle = commandTitle(for: shortcutID)
            commandResultCommand = trimmed
            commandResultBridgeName = credential?.bridgeName
            commandResultUpdatedAt = Date()
            return
        }
        commandRunning = true
        runningCommandShortcutID = shortcutID
        commandStatusText = "Running"
        commandOutputText = nil
        commandSucceeded = false
        commandResultTitle = commandTitle(for: shortcutID)
        commandResultCommand = trimmed
        commandResultBridgeName = credential?.bridgeName
        commandResultUpdatedAt = Date()
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
            let succeeded = ActionRunOutcome.succeeded(status: status, duplicate: result.duplicate)
            commandStatusText = status
            commandOutputText = output
            commandSucceeded = succeeded
            commandResultUpdatedAt = Date()
            recordCommandShortcutRun(shortcutID: shortcutID, status: status, result: output)
            recordTrustedWidgetCommandRun(
                shortcutID: shortcutID,
                status: status,
                result: output,
                succeeded: succeeded
            )
            try? await refresh()
            errorMessage = nil
        } catch {
            commandStatusText = "Request failed"
            commandOutputText = PopRocketErrorCopy.operationMessage(error)
            commandSucceeded = false
            commandResultUpdatedAt = Date()
            recordCommandShortcutRun(shortcutID: shortcutID, status: "Request failed", result: commandOutputText)
            recordTrustedWidgetCommandRun(
                shortcutID: shortcutID,
                status: "Request failed",
                result: commandOutputText,
                succeeded: false
            )
        }
    }

    func runCommandShortcut(_ shortcut: CommandShortcut) async {
        guard shortcut.bridgeID == credential?.bridgeID else {
            let message = "This command tile belongs to another bridge."
            errorMessage = message
            commandStatusText = "Unavailable"
            commandOutputText = message
            commandSucceeded = false
            commandResultTitle = shortcut.name
            commandResultCommand = shortcut.command
            commandResultBridgeName = credential?.bridgeName
            commandResultUpdatedAt = Date()
            return
        }
        await runCommand(shortcut.command, shortcutID: shortcut.id)
    }

    func clearCommandResult() {
        guard !commandRunning else { return }
        commandStatusText = nil
        commandOutputText = nil
        commandSucceeded = false
        commandResultTitle = nil
        commandResultCommand = nil
        commandResultBridgeName = nil
        commandResultUpdatedAt = nil
    }

    @discardableResult
    func saveCommandShortcut(name: String, command: String, existingID: UUID?) -> Bool {
        guard let bridgeID = credential?.bridgeID else {
            errorMessage = "Add a bridge before saving command tiles."
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
            syncWidgetActionSelectionMetadata()
            refreshCommandShortcutsForActiveBridge()
            refreshWidgetActionSelectionsForActiveBridge()
            errorMessage = nil
        }
        return saved
    }

    func deleteCommandShortcut(_ shortcut: CommandShortcut) {
        allCommandShortcuts.removeAll { $0.id == shortcut.id }
        removeWidgetActionSelection(kind: .command, actionID: shortcut.id.uuidString, bridgeID: shortcut.bridgeID)
        if persistCommandShortcuts() {
            refreshCommandShortcutsForActiveBridge()
            errorMessage = nil
        }
    }

    func isWidgetActionSelected(kind: WidgetActionKind, actionID: String) -> Bool {
        guard let bridgeID = credential?.bridgeID else {
            return false
        }
        let id = WidgetActionSelection.id(bridgeID: bridgeID, kind: kind, actionID: actionID)
        return allWidgetActionSelections.contains { $0.id == id }
    }

    @discardableResult
    func toggleWidgetActionSelection(kind: WidgetActionKind, actionID: String, title: String, subtitle: String?) -> Bool {
        guard let bridgeID = credential?.bridgeID else {
            errorMessage = "Add a bridge before adding widget actions."
            return false
        }
        let id = WidgetActionSelection.id(bridgeID: bridgeID, kind: kind, actionID: actionID)
        if let index = allWidgetActionSelections.firstIndex(where: { $0.id == id }) {
            allWidgetActionSelections.remove(at: index)
        } else {
            let nextOrder = (allWidgetActionSelections
                .filter { $0.bridgeID == bridgeID }
                .map(\.order)
                .max() ?? -1) + 1
            allWidgetActionSelections.append(
                WidgetActionSelection(
                    id: id,
                    bridgeID: bridgeID,
                    kind: kind,
                    actionID: actionID,
                    title: title,
                    subtitle: subtitle,
                    order: nextOrder,
                    addedAt: Date()
                )
            )
        }
        guard persistWidgetActionSelections() else {
            return false
        }
        refreshWidgetActionSelectionsForActiveBridge()
        errorMessage = nil
        return true
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

    private func recordTrustedWidgetCommandRun(shortcutID: UUID?, status: String, result: String?, succeeded: Bool) {
        guard let shortcutID else {
            return
        }
        recordTrustedWidgetActionRun(
            bridgeID: credential?.bridgeID,
            kind: .command,
            actionID: shortcutID.uuidString,
            title: commandTitle(for: shortcutID),
            status: status,
            message: result,
            succeeded: succeeded
        )
    }

    private func recordTrustedWidgetActionRun(
        bridgeID: String?,
        kind: WidgetActionKind,
        actionID: String,
        title: String,
        status: String,
        message: String?,
        succeeded: Bool
    ) {
        guard let bridgeID else {
            return
        }
        let recorded = (try? cache.recordTrustedWidgetActionRun(
            bridgeID: bridgeID,
            kind: kind,
            actionID: actionID,
            title: title,
            status: status,
            message: message,
            succeeded: succeeded
        )) ?? false
        if recorded {
            reloadWidgets()
        }
    }

    private func commandTitle(for shortcutID: UUID?) -> String {
        guard let shortcutID else {
            return "Ad-Hoc Command"
        }
        return commandShortcuts.first(where: { $0.id == shortcutID })?.name
            ?? allCommandShortcuts.first(where: { $0.id == shortcutID })?.name
            ?? "Command Tile"
    }

    func saveHealthMonitor(name: String, kind: String, host: String, port: String, url: String, timeoutSeconds: String, existingID: String?) async -> Bool {
        guard let credential else {
            errorMessage = "Add a bridge first."
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
            errorMessage = PopRocketErrorCopy.operationMessage(error)
            return false
        }
    }

    @discardableResult
    func deleteHealthMonitor(_ monitor: HealthMonitor) async -> Bool {
        guard let credential else {
            errorMessage = "Add a bridge first."
            return false
        }
        do {
            let privateKey = try signingPrivateKey()
            try await client.deleteHealthMonitor(id: monitor.id, credential: credential, privateKey: privateKey)
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = PopRocketErrorCopy.operationMessage(error)
            return false
        }
    }

    func saveWOLTarget(name: String, mac: String, ipAddress: String, broadcastIP: String, udpPort: String, existingID: String?) async -> Bool {
        guard let credential else {
            errorMessage = "Add a bridge first."
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
            errorMessage = PopRocketErrorCopy.operationMessage(error)
            return false
        }
    }

    @discardableResult
    func deleteWOLTarget(_ target: WOLTarget) async -> Bool {
        guard let credential else {
            errorMessage = "Add a bridge first."
            return false
        }
        do {
            let privateKey = try signingPrivateKey()
            try await client.deleteWOLTarget(id: target.id, credential: credential, privateKey: privateKey)
            wakeStates[target.id] = nil
            removeWidgetActionSelection(kind: .wol, actionID: target.id, bridgeID: credential.bridgeID)
            try await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = PopRocketErrorCopy.operationMessage(error)
            return false
        }
    }

    func wake(_ target: WOLTarget) async {
        let actionBridgeName = credential?.bridgeName
        guard let bridgeID = credential?.bridgeID else {
            wakeStates[target.id] = WOLActionState(
                status: "Unavailable",
                message: "Add a bridge before waking devices.",
                running: false,
                succeeded: false,
                bridgeName: actionBridgeName,
                updatedAt: Date()
            )
            return
        }
        if let reason = wolWakeUnavailableReason(for: target) {
            wakeStates[target.id] = WOLActionState(
                status: "Unavailable",
                message: reason,
                running: false,
                succeeded: false,
                bridgeName: actionBridgeName,
                updatedAt: Date()
            )
            return
        }
        wakeStates[target.id] = WOLActionState(
            status: "Running",
            message: nil,
            running: true,
            succeeded: false,
            bridgeName: actionBridgeName,
            updatedAt: Date()
        )
        do {
            let result = try await NotificationActionRouter().route(
                actionID: "wol:\(target.id)",
                eventID: nil,
                confirmed: true,
                bridgeID: bridgeID
            )
            let status = result.status ?? (result.duplicate == true ? "accepted" : "completed")
            let succeeded = ActionRunOutcome.succeeded(status: status, duplicate: result.duplicate)
            wakeStates[target.id] = WOLActionState(
                status: ActionRunOutcome.displayStatus(status: status, duplicate: result.duplicate),
                message: result.resultMessage,
                running: false,
                succeeded: succeeded,
                bridgeName: actionBridgeName,
                updatedAt: Date()
            )
            recordTrustedWidgetActionRun(
                bridgeID: bridgeID,
                kind: .wol,
                actionID: target.id,
                title: "Wake \(target.name)",
                status: status,
                message: result.resultMessage,
                succeeded: succeeded
            )
            try? await refresh()
            errorMessage = nil
        } catch {
            let message = PopRocketErrorCopy.operationMessage(error)
            wakeStates[target.id] = WOLActionState(
                status: "Failed",
                message: message,
                running: false,
                succeeded: false,
                bridgeName: actionBridgeName,
                updatedAt: Date()
            )
            recordTrustedWidgetActionRun(
                bridgeID: bridgeID,
                kind: .wol,
                actionID: target.id,
                title: "Wake \(target.name)",
                status: "Request failed",
                message: message,
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
            try? cache.clearActiveDashboardState()
            if let credential {
                loadCachedRemoteState(for: credential)
            }
            reloadWidgets()
        }
        if credential == nil {
            clearRemoteBridgeState()
            bridgeStatusText = "No bridge"
        } else if !bridgeReachable {
            bridgeHealth = nil
            bridgeStatusText = "Connected"
        }
        migrateUnscopedCommandShortcutsIfNeeded()
        refreshCommandShortcutsForActiveBridge()
        syncWidgetActionSelectionMetadata()
        refreshWidgetActionSelectionsForActiveBridge()
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
        saveCachedRemoteState(bridgeID: credential.bridgeID)
        syncWidgetActionSelectionMetadata()
        refreshWidgetActionSelectionsForActiveBridge()
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

    private func saveCachedRemoteState(
        bridgeID: String,
        bridgeReachable bridgeReachableOverride: Bool? = nil,
        bridgeStatus bridgeStatusOverride: String? = nil
    ) {
        let bridgeName = credential?.bridgeID == bridgeID
            ? credential?.bridgeName
            : bridges.first { $0.bridgeID == bridgeID }?.bridgeName
        let cachedBridgeReachable = bridgeReachableOverride ?? (bridgeReachable ? true : nil)
        let cachedBridgeStatus = bridgeStatusOverride ?? (bridgeReachable ? bridgeStatusText : nil)
        let state = try? cache.saveDashboardState(
            bridgeID: bridgeID,
            bridgeName: bridgeName,
            bridgeReachable: cachedBridgeReachable,
            bridgeStatus: cachedBridgeStatus,
            healthMonitors: healthMonitors,
            wolTargets: wolTargets,
            healthMonitorsUpdatedAt: healthMonitorsUpdatedAt,
            wolTargetsUpdatedAt: wolTargetsUpdatedAt
        )
        dashboardStateUpdatedAt = state?.writtenAt ?? dashboardStateUpdatedAt
    }

    private func saveActiveBridgeConnectionState(bridgeReachable: Bool, bridgeStatus: String) {
        guard let bridgeID = credential?.bridgeID else {
            return
        }
        saveCachedRemoteState(
            bridgeID: bridgeID,
            bridgeReachable: bridgeReachable,
            bridgeStatus: bridgeStatus
        )
    }

    private func updateCachedBridgeName(bridgeID: String, bridgeName: String?) {
        guard let state = try? cache.updateDashboardBridgeName(bridgeID: bridgeID, bridgeName: bridgeName) else {
            return
        }
        dashboardStateUpdatedAt = state.writtenAt
        reloadWidgets()
    }

    private func clearSectionErrors() {
        statusSnapshotsErrorMessage = nil
        healthMonitorsErrorMessage = nil
        wolTargetsErrorMessage = nil
        activityErrorMessage = nil
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func refreshStatusSnapshots(credential: PairingCredential, privateKey: Curve25519.Signing.PrivateKey) async {
        guard Self.scopes(credential.scopes, include: "cards:read") else {
            cards = []
            statusSnapshotsErrorMessage = Self.missingScopeMessage("cards:read")
            try? cache.saveCards([])
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
                try? cache.saveCards([])
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
            syncWidgetActionSelectionMetadata()
            refreshWidgetActionSelectionsForActiveBridge()
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

    private func loadWidgetActionSelections() {
        do {
            allWidgetActionSelections = try cache.loadWidgetActionSelections()?.selections ?? []
            refreshWidgetActionSelectionsForActiveBridge()
        } catch {
            allWidgetActionSelections = []
            widgetActionSelections = []
            try? cache.saveWidgetActionSelections([])
            errorMessage = "Could not load widget actions."
        }
    }

    private func persistWidgetActionSelections() -> Bool {
        do {
            try cache.saveWidgetActionSelections(allWidgetActionSelections)
            reloadWidgets()
            return true
        } catch {
            errorMessage = "Could not save widget actions."
            return false
        }
    }

    private func removeWidgetActionSelection(kind: WidgetActionKind, actionID: String, bridgeID: String?) {
        guard let bridgeID else {
            return
        }
        let id = WidgetActionSelection.id(bridgeID: bridgeID, kind: kind, actionID: actionID)
        let oldCount = allWidgetActionSelections.count
        allWidgetActionSelections.removeAll { $0.id == id }
        if allWidgetActionSelections.count != oldCount {
            _ = persistWidgetActionSelections()
            refreshWidgetActionSelectionsForActiveBridge()
        }
    }

    private func refreshWidgetActionSelectionsForActiveBridge() {
        guard let bridgeID = credential?.bridgeID else {
            widgetActionSelections = []
            return
        }
        widgetActionSelections = allWidgetActionSelections
            .filter { $0.bridgeID == bridgeID }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.addedAt < rhs.addedAt
            }
    }

    private func syncWidgetActionSelectionMetadata() {
        guard !allWidgetActionSelections.isEmpty else {
            return
        }
        var changed = false
        for index in allWidgetActionSelections.indices {
            switch allWidgetActionSelections[index].kind {
            case .command:
                guard
                    let uuid = UUID(uuidString: allWidgetActionSelections[index].actionID),
                    let shortcut = allCommandShortcuts.first(where: {
                        $0.id == uuid && $0.bridgeID == allWidgetActionSelections[index].bridgeID
                    })
                else {
                    continue
                }
                if allWidgetActionSelections[index].title != shortcut.name {
                    allWidgetActionSelections[index].title = shortcut.name
                    changed = true
                }
                if allWidgetActionSelections[index].subtitle != shortcut.command {
                    allWidgetActionSelections[index].subtitle = shortcut.command
                    changed = true
                }
            case .wol:
                guard
                    allWidgetActionSelections[index].bridgeID == credential?.bridgeID,
                    let target = wolTargets.first(where: { $0.id == allWidgetActionSelections[index].actionID })
                else {
                    continue
                }
                let title = "Wake \(target.name)"
                let subtitle = target.ipAddress ?? target.broadcastIP
                if allWidgetActionSelections[index].title != title {
                    allWidgetActionSelections[index].title = title
                    changed = true
                }
                if allWidgetActionSelections[index].subtitle != subtitle {
                    allWidgetActionSelections[index].subtitle = subtitle
                    changed = true
                }
            }
        }
        if changed {
            _ = persistWidgetActionSelections()
        }
    }

    private func loadCommandShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: commandShortcutsKey) else {
            allCommandShortcuts = []
            commandShortcuts = []
            try? cache.saveCommandShortcuts([])
            reloadWidgets()
            return
        }
        do {
            allCommandShortcuts = try PopRocketCoding.decoder.decode([CommandShortcut].self, from: data)
            try? cache.saveCommandShortcuts(allCommandShortcuts)
            syncWidgetActionSelectionMetadata()
            refreshCommandShortcutsForActiveBridge()
            refreshWidgetActionSelectionsForActiveBridge()
            reloadWidgets()
        } catch {
            allCommandShortcuts = []
            commandShortcuts = []
            try? cache.saveCommandShortcuts([])
            reloadWidgets()
            errorMessage = "Could not load saved command tiles."
        }
    }

    private func persistCommandShortcuts() -> Bool {
        do {
            let data = try PopRocketCoding.encoder.encode(allCommandShortcuts)
            UserDefaults.standard.set(data, forKey: commandShortcutsKey)
            try cache.saveCommandShortcuts(allCommandShortcuts)
            reloadWidgets()
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
        let message = PopRocketErrorCopy.operationMessage(error)
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
        "\(prefix): \(PopRocketErrorCopy.operationMessage(error))"
    }

    private static func missingScopeMessage(_ scope: String) -> String {
        let capability: String
        switch scope {
        case "cards:read":
            capability = "status snapshots"
        case "monitor:read":
            capability = "health checks"
        case "monitor:write":
            capability = "health check management"
        case "wol:read":
            capability = "Wake-on-LAN devices"
        case "wol:manage":
            capability = "device management"
        case "audit:read":
            capability = "activity history"
        case "command:run":
            capability = "command execution"
        default:
            capability = scope
        }
        return "This bridge cannot read \(capability). Reconnect it in Settings."
    }

    private static func isUnsupportedEndpoint(_ error: Error) -> Bool {
        guard let bridgeError = error as? BridgeHTTPError else {
            return false
        }
        return bridgeError.statusCode == 404
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
