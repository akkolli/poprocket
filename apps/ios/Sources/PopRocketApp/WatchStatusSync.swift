#if os(iOS) && canImport(WatchConnectivity)
import Foundation
import PopRocketKit
import WatchConnectivity

final class WatchStatusSync: NSObject, WCSessionDelegate {
    static let shared = WatchStatusSync()

    private var session: WCSession?
    private var pendingSnapshot: WatchDashboardSnapshot?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        if self.session !== session {
            self.session = session
            session.delegate = self
        }
        if session.activationState == .notActivated {
            session.activate()
        }
    }

    func publish(_ snapshot: WatchDashboardSnapshot) {
        pendingSnapshot = snapshot
        activate()
        sendPendingSnapshot()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        sendPendingSnapshot()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["type"] as? String == "wake_wol",
              let bridgeID = message["bridge_id"] as? String,
              let targetID = message["target_id"] as? String,
              !bridgeID.isEmpty,
              !targetID.isEmpty
        else {
            replyHandler([
                "ok": false,
                "status": "Rejected",
                "message": "Unsupported watch request."
            ])
            return
        }

        Task {
            let response = await Self.runTrustedWake(bridgeID: bridgeID, targetID: targetID)
            replyHandler(response)
        }
    }

    private static func runTrustedWake(bridgeID: String, targetID: String) async -> [String: Any] {
        let cache = AppGroupCache()
        do {
            let selection = try cache.requireWidgetActionSelection(
                bridgeID: bridgeID,
                kind: .wol,
                actionID: targetID
            )
            let result = try await NotificationActionRouter().route(
                actionID: "wol:\(targetID)",
                eventID: nil,
                confirmed: true,
                bridgeID: bridgeID
            )
            let status = result.status ?? (result.duplicate == true ? "accepted" : "completed")
            let succeeded = ActionRunOutcome.succeeded(status: status, duplicate: result.duplicate)
            try? cache.recordWidgetActionRun(
                WidgetActionRunRecord(
                    id: WidgetActionSelection.id(bridgeID: bridgeID, kind: .wol, actionID: targetID),
                    bridgeID: bridgeID,
                    kind: .wol,
                    actionID: targetID,
                    title: selection.title,
                    status: status,
                    message: result.resultMessage,
                    succeeded: succeeded,
                    ranAt: Date()
                )
            )
            return [
                "ok": succeeded,
                "status": ActionRunOutcome.displayStatus(status: status, duplicate: result.duplicate),
                "message": result.resultMessage ?? "",
                "target_id": targetID
            ]
        } catch {
            return [
                "ok": false,
                "status": "Failed",
                "message": PopRocketErrorCopy.operationMessage(error),
                "target_id": targetID
            ]
        }
    }

    private func sendPendingSnapshot() {
        guard let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled,
              let pendingSnapshot
        else {
            return
        }

        do {
            let data = try PopRocketCoding.encoder.encode(pendingSnapshot)
            try session.updateApplicationContext(["dashboard_snapshot": data])
        } catch {
            if Self.isExpectedInactiveWatchError(error) {
                return
            }
            print("PopRocket watch sync failed: \(error)")
        }
    }

    private static func isExpectedInactiveWatchError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == WCErrorDomain &&
            nsError.code == WCError.Code.watchAppNotInstalled.rawValue
    }
}
#endif
