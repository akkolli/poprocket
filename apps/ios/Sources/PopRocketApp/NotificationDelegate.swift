import PopRocketKit
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static func registerCategories() {
        let ack = UNNotificationAction(identifier: "ack", title: "Ack")
        let wake = UNNotificationAction(identifier: "wake_nas", title: "Wake NAS", options: [.authenticationRequired])
        let category = UNNotificationCategory(
            identifier: "POPROCKET_EVENT",
            actions: [ack, wake],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let eventID = userInfo["event_id"] as? String
        let router = NotificationActionRouter()
        try? await router.route(
            actionID: response.actionIdentifier,
            eventID: eventID,
            confirmed: response.actionIdentifier != "ack"
        )
    }
}
