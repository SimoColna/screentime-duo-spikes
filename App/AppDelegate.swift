import BackgroundTasks
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
        return true
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
