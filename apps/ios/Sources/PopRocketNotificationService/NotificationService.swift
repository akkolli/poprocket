import PopRocketKit
import UserNotifications

public final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    public override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        bestAttemptContent = content

        if let eventID = request.content.userInfo["event_id"] as? String {
            content.threadIdentifier = request.content.userInfo["bridge_id"] as? String ?? "poprocket"
            content.userInfo["event_id"] = eventID
        }

        contentHandler(content)
    }

    public override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
