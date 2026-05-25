import PopRocketKit
import SwiftUI
import UserNotifications

@main
public struct PopRocketApp: App {
    @StateObject private var model = DashboardModel()
    private let notificationDelegate = NotificationDelegate()

    public init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationDelegate.registerCategories()
    }

    public var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(model)
                .task {
                    await model.load()
                }
        }
    }
}
