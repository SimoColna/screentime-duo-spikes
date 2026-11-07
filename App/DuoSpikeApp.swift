import SwiftUI

@main
struct DuoSpikeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                model.refresh()
                Task { await model.syncNow(reason: "foreground") }
            case .background:
                AppDelegate.scheduleAppRefresh()
            default:
                break
            }
        }
    }
}
