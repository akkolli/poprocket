import PopRocketKit
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static func registerCategories() {
        let ack = UNNotificationAction(identifier: "ack", title: "Ack")
        let category = UNNotificationCategory(
            identifier: "POPROCKET_EVENT",
            actions: [ack],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let eventID = userInfo["event_id"] as? String
        let bridgeID = userInfo["bridge_id"] as? String
        let router = NotificationActionRouter()
        try? await router.route(
            actionID: response.actionIdentifier,
            eventID: eventID,
            confirmed: response.actionIdentifier != "ack",
            bridgeID: bridgeID
        )
    }
}
