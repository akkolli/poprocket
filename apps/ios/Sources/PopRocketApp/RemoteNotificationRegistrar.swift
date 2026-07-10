#if os(iOS)
import PopRocketKit
import UIKit
import UserNotifications

final class PopRocketAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task {
            await RemoteNotificationRegistrar.shared.registerIfAlreadyAuthorized()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            await RemoteNotificationRegistrar.shared.updateDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task {
            await RemoteNotificationRegistrar.shared.recordRegistrationFailure(error)
        }
    }
}

@MainActor
final class RemoteNotificationRegistrar {
    static let shared = RemoteNotificationRegistrar()

    private let bridgeStore: BridgeCredentialStore
    private let bridgeClient: BridgeClient
    private let notificationCenter: UNUserNotificationCenter
    private var apnsToken: String?
    private var lastRegisteredKey: String?

    init(
        bridgeStore: BridgeCredentialStore = BridgeCredentialStore(),
        bridgeClient: BridgeClient = BridgeClient(),
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.bridgeStore = bridgeStore
        self.bridgeClient = bridgeClient
        self.notificationCenter = notificationCenter
    }

    func requestAuthorizationAndRegister() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("PopRocket notification authorization failed: \(error)")
        }
    }

    func registerIfAlreadyAuthorized() async {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .notDetermined, .denied:
            break
        @unknown default:
            break
        }
    }

    func updateDeviceToken(_ deviceToken: Data) async {
        apnsToken = Self.hexToken(from: deviceToken)
        await registerActiveCredentialIfPossible()
    }

    @discardableResult
    func registerActiveCredentialIfPossible() async -> Bool {
        guard let apnsToken else {
            return false
        }
        do {
            guard let credential = try bridgeStore.load().activeCredential,
                  credential.relayURL != nil,
                  credential.relayAccessToken != nil
            else {
                return false
            }
            let key = "\(credential.bridgeID)|\(credential.deviceID)|\(credential.pairedAt.timeIntervalSince1970)|ios|\(apnsToken)"
            guard key != lastRegisteredKey else {
                return true
            }
            _ = try await bridgeClient.registerDeviceForNotifications(
                apnsToken: apnsToken,
                platform: "ios",
                credential: credential
            )
            lastRegisteredKey = key
            return true
        } catch {
            print("PopRocket notification registration failed: \(error)")
            return false
        }
    }

    func recordRegistrationFailure(_ error: Error) async {
        print("PopRocket APNs registration failed: \(error)")
    }

    private static func hexToken(from data: Data) -> String {
        data.map { String(format: "%02.2hhx", $0) }.joined()
    }
}
#endif
