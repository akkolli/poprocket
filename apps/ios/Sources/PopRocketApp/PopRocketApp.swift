import PopRocketKit
import SwiftUI
import UserNotifications

@main
public struct PopRocketApp: App {
    @StateObject private var model = DashboardModel()
    private let notificationDelegate = NotificationDelegate()
#if os(iOS)
    @UIApplicationDelegateAdaptor(PopRocketAppDelegate.self) private var appDelegate
#endif

    public init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationDelegate.registerCategories()
#if os(iOS) && canImport(WatchConnectivity)
        WatchStatusSync.shared.activate()
#endif
    }

    public var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(model)
                .task {
                    let environment = ProcessInfo.processInfo.environment
                    await model.load()
                    if let payload = environment["POPROCKET_PAIRING_PAYLOAD"], !payload.isEmpty {
                        await model.completePairing(rawPayload: payload)
                    }
                    if let actionID = environment["POPROCKET_RUN_ACTION_ID"], !actionID.isEmpty {
                        let confirmed = environment["POPROCKET_RUN_CONFIRMED"].flatMap(Bool.init) ?? (actionID != "ack")
                        await model.runAction(
                            actionID: actionID,
                            eventID: environment["POPROCKET_RUN_EVENT_ID"],
                            confirmed: confirmed
                        )
                    }
                }
        }
    }
}
