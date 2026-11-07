import BackgroundTasks
import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var refreshTaskID: String {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.first
            ?? "duospike.refresh"
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            Self.handleAppRefresh(task)
        }
        // Le push silenziose di CKDatabaseSubscription non richiedono il permesso notifiche.
        application.registerForRemoteNotifications()
        return true
    }

    // MARK: Scene (necessaria per ricevere l'accettazione del CKShare in un'app SwiftUI)

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // MARK: Push silenziose CloudKit

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in AppModel.shared.appLog("push.registered") }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in AppModel.shared.appLog("push.registerError", String(describing: error)) }
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let reason = CKNotification(fromRemoteNotificationDictionary: userInfo) != nil ? "ckPush" : "push"
        Task { @MainActor in
            let ok = await AppModel.shared.syncNow(reason: reason)
            completionHandler(ok ? .newData : .failed)
        }
    }

    // MARK: Background refresh (fallback domanda 2)

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Task { @MainActor in AppModel.shared.appLog("bg.scheduleError", String(describing: error)) }
        }
    }

    private static func handleAppRefresh(_ task: BGTask) {
        scheduleAppRefresh()
        let work = Task { @MainActor in
            AppModel.shared.appLog("bg.refresh", "start")
            let ok = await AppModel.shared.syncNow(reason: "bgRefresh")
            task.setTaskCompleted(success: ok)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
