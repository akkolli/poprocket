import AppIntents
import PopRocketKit
#if canImport(WidgetKit)
import WidgetKit
#endif

public struct RunActionIntent: AppIntent {
    public static var title: LocalizedStringResource = "Run PopRocket Action"
    public static var description = IntentDescription("Runs a scoped PopRocket action.")

    @Parameter(title: "Action ID")
    public var actionID: String

    @Parameter(title: "Event ID")
    public var eventID: String?

    @Parameter(title: "Bridge ID")
    public var bridgeID: String?

    public init() {
        self.actionID = "ack"
        self.eventID = nil
        self.bridgeID = nil
    }

    public init(actionID: String, eventID: String?) {
        self.actionID = actionID
        self.eventID = eventID
        self.bridgeID = nil
    }

    public init(actionID: String, eventID: String?, bridgeID: String?) {
        self.actionID = actionID
        self.eventID = eventID
        self.bridgeID = bridgeID
    }

    public func perform() async throws -> some IntentResult {
        do {
            let selection = try authorizeWidgetActionIfNeeded()
            let result = try await NotificationActionRouter().route(
                actionID: actionID,
                eventID: eventID,
                confirmed: actionID != "ack",
                bridgeID: bridgeID
            )
            let status = result.status ?? (result.duplicate == true ? "accepted" : "completed")
            recordWidgetRun(
                status: status,
                message: result.resultMessage,
                succeeded: ActionRunOutcome.succeeded(status: status, duplicate: result.duplicate),
                title: selection?.title
            )
            return .result()
        } catch {
            if (error as? WidgetActionAuthorizationError) == nil {
                recordWidgetRun(status: "failed", message: PopRocketErrorCopy.operationMessage(error), succeeded: false, title: nil)
            }
            throw error
        }
    }

    private func authorizeWidgetActionIfNeeded() throws -> WidgetActionSelection? {
        guard actionID.hasPrefix("wol:") else {
            if eventID == nil && actionID != "ack" {
                throw WidgetActionAuthorizationError.notTrusted
            }
            return nil
        }
        guard let bridgeID else {
            throw WidgetActionAuthorizationError.notTrusted
        }
        let targetID = String(actionID.dropFirst(4))
        guard !targetID.isEmpty else {
            throw WidgetActionAuthorizationError.notTrusted
        }
        return try AppGroupCache().requireWidgetActionSelection(
            bridgeID: bridgeID,
            kind: .wol,
            actionID: targetID
        )
    }

    private func recordWidgetRun(status: String, message: String?, succeeded: Bool, title: String?) {
        guard let record = widgetRunRecord(status: status, message: message, succeeded: succeeded, title: title) else {
            return
        }
        try? AppGroupCache().recordWidgetActionRun(record)
        Self.reloadWidgets()
    }

    private func widgetRunRecord(status: String, message: String?, succeeded: Bool, title: String?) -> WidgetActionRunRecord? {
        guard actionID.hasPrefix("wol:"), let bridgeID else {
            return nil
        }
        let targetID = String(actionID.dropFirst(4))
        guard !targetID.isEmpty else {
            return nil
        }
        return WidgetActionRunRecord(
            id: WidgetActionSelection.id(bridgeID: bridgeID, kind: .wol, actionID: targetID),
            bridgeID: bridgeID,
            kind: .wol,
            actionID: targetID,
            title: title ?? "Wake",
            status: status,
            message: message,
            succeeded: succeeded,
            ranAt: Date()
        )
    }

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

public struct RunCommandShortcutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Run PopRocket Command Tile"
    public static var description = IntentDescription("Runs a saved command tile through the paired bridge.")

    @Parameter(title: "Shortcut ID")
    public var shortcutID: String

    public init() {
        self.shortcutID = ""
    }

    public init(shortcutID: String) {
        self.shortcutID = shortcutID
    }

    public func perform() async throws -> some IntentResult {
        guard
            let uuid = UUID(uuidString: shortcutID),
            let shortcuts = try AppGroupCache().loadCommandShortcuts()?.shortcuts,
            let shortcut = shortcuts.first(where: { $0.id == uuid }),
            let bridgeID = shortcut.bridgeID
        else {
            throw URLError(.fileDoesNotExist)
        }
        _ = try AppGroupCache().requireWidgetActionSelection(
            bridgeID: bridgeID,
            kind: .command,
            actionID: shortcut.id.uuidString
        )
        do {
            let result = try await NotificationActionRouter().route(
                actionID: "command:run",
                eventID: nil,
                confirmed: true,
                bridgeID: bridgeID,
                parameters: ["command": shortcut.command]
            )
            let status = result.status ?? (result.duplicate == true ? "accepted" : "completed")
            recordWidgetRun(
                shortcut: shortcut,
                status: status,
                message: result.resultMessage,
                succeeded: ActionRunOutcome.succeeded(status: status, duplicate: result.duplicate)
            )
            return .result()
        } catch {
            recordWidgetRun(shortcut: shortcut, status: "failed", message: PopRocketErrorCopy.operationMessage(error), succeeded: false)
            throw error
        }
    }

    private func recordWidgetRun(shortcut: CommandShortcut, status: String, message: String?, succeeded: Bool) {
        guard let bridgeID = shortcut.bridgeID else {
            return
        }
        let record = WidgetActionRunRecord(
            id: WidgetActionSelection.id(bridgeID: bridgeID, kind: .command, actionID: shortcut.id.uuidString),
            bridgeID: bridgeID,
            kind: .command,
            actionID: shortcut.id.uuidString,
            title: shortcut.name,
            status: status,
            message: message,
            succeeded: succeeded,
            ranAt: Date()
        )
        try? AppGroupCache().recordWidgetActionRun(record)
        Self.reloadWidgets()
    }

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
