import DeviceActivity
import FamilyControls
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    /// Unico punto in cui si sceglie il backend: per lo spike il fake locale.
    static let shared = AppModel(sync: LocalFakeSyncService())

    // MARK: Stato pubblicato

    @Published private(set) var authStatus: AuthorizationStatus = .notDetermined
    @Published var selection: FamilyActivitySelection {
        didSet { settings.selectionData = try? JSONEncoder().encode(selection) }
    }
    @Published var thresholdMinutes: Int {
        didSet { settings.thresholdMinutes = thresholdMinutes }
    }
    @Published var includesPastActivity: Bool {
        didSet { settings.includesPastActivity = includesPastActivity }
    }
    @Published var displayName: String {
        didSet { settings.displayName = displayName }
    }
    @Published var probeNetwork: Bool {
        didSet { settings.probeNetwork = probeNetwork }
    }
    @Published var probeURL: String {
        didSet { settings.probeURL = probeURL }
    }
    @Published var probeNotification: Bool {
        didSet {
            settings.probeNotification = probeNotification
            if probeNotification { Task { await requestNotificationPermission() } }
        }
    }
    @Published var fakeOffline = false {
        didSet { fakeSync?.isOffline = fakeOffline }
    }

    @Published private(set) var monitoredActivities: [String] = []
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var userId: String?
    @Published private(set) var pairing: Pairing?
    @Published private(set) var lastInvite: Invite?
    @Published private(set) var pairResults: [DayResult] = []
    @Published private(set) var lastSyncDescription = "mai"
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy = false

    let settings: SharedSettings
    let sync: SyncService
    private let center = DeviceActivityCenter()

    var fakeSync: LocalFakeSyncService? { sync as? LocalFakeSyncService }

    init(sync: SyncService) {
        let s = SharedSettings()
        self.sync = sync
        settings = s
        selection = s.selectionData.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()
        thresholdMinutes = s.thresholdMinutes
        includesPastActivity = s.includesPastActivity
        displayName = s.displayName.isEmpty ? UIDevice.current.name : s.displayName
        probeNetwork = s.probeNetwork
        probeURL = s.probeURL
        probeNotification = s.probeNotification
        userId = s.userId
        refresh()
    }

    // MARK: Derivati

    var localResults: [DayResult] {
        DayResult.local(from: log, userId: userId ?? "unknown", displayName: displayName,
                        currentThreshold: settings.activeThresholdMinutes ?? thresholdMinutes,
                        startDay: settings.monitoringStartDay)
    }

    var myRemoteResults: [DayResult] { pairResults.filter { $0.userId == userId } }
    var partnerResults: [DayResult] { pairResults.filter { $0.userId != userId } }
    var partner: PairMember? { userId.flatMap { pairing?.partner(of: $0) } }

    var diagnoses: [ThresholdDiagnostics.Day] { ThresholdDiagnostics.diagnose(log: log) }

    var authStatusText: String {
        switch authStatus {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .approved: return "approved"
        @unknown default: return "unknown"
        }
    }

    var selectionSummary: String {
        "\(selection.applicationTokens.count) app, \(selection.categoryTokens.count) categorie, \(selection.webDomainTokens.count) domini"
    }

    var activeThresholdText: String {
        guard let minutes = settings.activeThresholdMinutes else { return "-" }
        let ladder = settings.activeLadderPercents.map { "\($0)%" }.joined(separator: "/")
        return ladder.isEmpty ? "\(minutes) min" : "\(minutes) min (gradini \(ladder))"
    }

    // MARK: Screen Time

    func refresh() {
        authStatus = AuthorizationCenter.shared.authorizationStatus
        monitoredActivities = center.activities.map(\.rawValue)
        log = EventLog.readAll()
    }

    func appLog(_ kind: String, _ detail: String = "") {
        EventLog.append(LogEntry(source: "app", kind: kind, detail: detail,
                                 threshold: settings.activeThresholdMinutes))
        log = EventLog.readAll()
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            appLog("auth", "ok")
        } catch {
            appLog("auth.error", String(describing: error))
        }
        refresh()
    }

    func startMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let steps = ThresholdDiagnostics.steps(for: thresholdMinutes)
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [.threshold: makeEvent(minutes: thresholdMinutes)]
        for step in steps {
            events[.ladder(step.percent)] = makeEvent(minutes: step.minutes)
        }
        do {
            // Sovrascrive eventuale schedule/eventi precedenti con lo stesso nome.
            try center.startMonitoring(.daily, during: schedule, events: events)
            settings.activeThresholdMinutes = thresholdMinutes
            settings.activeLadderPercents = steps.map(\.percent)
            if settings.monitoringStartDay == nil {
                settings.monitoringStartDay = DayKey.string(from: Date())
            }
            let ladder = steps.map { "\($0.percent)%=\($0.minutes)m" }.joined(separator: " ")
            appLog(LogKind.monitorStart, "soglia \(thresholdMinutes) min [\(ladder)], \(selectionSummary), includesPastActivity=\(includesPastActivity)")
        } catch {
            appLog("monitor.error", String(describing: error))
        }
        refresh()
    }

    private func makeEvent(minutes: Int) -> DeviceActivityEvent {
        let threshold = DateComponents(minute: minutes)
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(applications: selection.applicationTokens,
                                       categories: selection.categoryTokens,
                                       webDomains: selection.webDomainTokens,
                                       threshold: threshold,
                                       includesPastActivity: includesPastActivity)
        } else {
            return DeviceActivityEvent(applications: selection.applicationTokens,
                                       categories: selection.categoryTokens,
                                       webDomains: selection.webDomainTokens,
                                       threshold: threshold)
        }
    }

    func stopMonitoring() {
        center.stopMonitoring([.daily])
        appLog("monitor.stop")
        refresh()
    }

    func clearLog() {
        EventLog.clear()
        refresh()
    }

    private func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            appLog("notifications.auth", granted ? "granted" : "denied")
        } catch {
            appLog("notifications.auth", String(describing: error))
        }
    }

    // MARK: Coppia (via SyncService)

    func createInvite() async {
        await busy {
            let invite = try await self.sync.createInvite(displayName: self.displayName)
            self.lastInvite = invite
            self.pairing = try await self.sync.pairing()
            self.appLog("pair.invite", "codice \(invite.code)")
        }
        await syncNow(reason: "invite")
    }

    func acceptInvite(code: String) async {
        await busy {
            self.pairing = try await self.sync.acceptInvite(code: code, displayName: self.displayName)
            self.appLog("pair.accept", "codice \(code)")
        }
        await syncNow(reason: "accept")
    }

    func leavePair() async {
        await busy {
            try await self.sync.leavePair()
            self.pairing = nil
            self.pairResults = []
            self.lastInvite = nil
            self.appLog("pair.leave")
        }
    }

    /// Solo con il backend finto: imposta lo stato di oggi del partner simulato.
    func simulatePartnerToday(exceeded: Bool) async {
        fakeSync?.simulatePartner(day: DayKey.string(from: Date()), exceeded: exceeded, threshold: 30)
        await syncNow(reason: "simulazione")
    }

    func wipeFakeBackend() {
        fakeSync?.wipe()
        settings.userId = nil
        userId = nil
        pairing = nil
        pairResults = []
        lastInvite = nil
        appLog("fake.wipe")
    }

    // MARK: Sync

    /// Pubblica i DayResult ricalcolati dal log e scarica quelli della coppia.
    /// Chiamata in foreground, da BGAppRefresh e a mano. Idempotente: nessuna coda di invio.
    @discardableResult
    func syncNow(reason: String) async -> Bool {
        refresh()
        do {
            if userId == nil {
                let id = try await sync.currentUserId()
                userId = id
                settings.userId = id
            }
            pairing = try await sync.pairing()
            guard pairing != nil else {
                lastSyncDescription = "\(Self.timeString(Date())) (\(reason)): nessuna coppia"
                return true
            }
            let mine = localResults
            try await sync.upload(mine)
            pairResults = try await sync.fetchPairResults(days: 7)
            lastError = nil
            lastSyncDescription = "\(Self.timeString(Date())) (\(reason)): inviati \(mine.count), ricevuti \(pairResults.count)"
            appLog("sync.ok", lastSyncDescription)
            return true
        } catch {
            lastError = String(describing: error)
            appLog("sync.error", "\(reason): \(error)")
            return false
        }
    }

    private func busy(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            lastError = nil
        } catch {
            lastError = String(describing: error)
            appLog("error", String(describing: error))
        }
    }

    static func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
