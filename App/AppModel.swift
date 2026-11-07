import CloudKit
import DeviceActivity
import FamilyControls
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

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
    @Published var probeCloudKit: Bool {
        didSet { settings.probeCloudKit = probeCloudKit }
    }

    @Published private(set) var monitoredActivities: [String] = []
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var role: CoupleRole
    @Published private(set) var userId: String?
    @Published private(set) var cloudResults: [DayResult] = []
    @Published private(set) var participantsDescription = "-"
    @Published private(set) var lastSyncDescription = "mai"
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy = false

    let settings: SharedSettings
    let cloud = CloudSync()
    private let center = DeviceActivityCenter()
    private let sharingDelegate = SharingDelegate()

    private init() {
        let s = SharedSettings()
        settings = s
        selection = s.selectionData.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()
        thresholdMinutes = s.thresholdMinutes
        includesPastActivity = s.includesPastActivity
        displayName = s.displayName.isEmpty ? UIDevice.current.name : s.displayName
        probeNetwork = s.probeNetwork
        probeCloudKit = s.probeCloudKit
        role = CoupleRole(rawValue: s.role) ?? .none
        userId = s.userId
        sharingDelegate.onEvent = { [weak self] message in self?.appLog("sharing", message) }
        refresh()
    }

    // MARK: Derivati

    var zoneID: CKRecordZone.ID? {
        guard let name = settings.zoneName, let owner = settings.zoneOwnerName else { return nil }
        return CKRecordZone.ID(zoneName: name, ownerName: owner)
    }

    var localResults: [DayResult] {
        DayResult.local(from: log, userId: userId ?? "unknown", displayName: displayName,
                        currentThreshold: settings.activeThresholdMinutes ?? thresholdMinutes,
                        startDay: settings.monitoringStartDay)
    }

    var myCloudResults: [DayResult] { cloudResults.filter { $0.userId == userId } }
    var partnerResults: [DayResult] { cloudResults.filter { $0.userId != userId } }

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
        settings.activeThresholdMinutes.map { "\($0) min" } ?? "-"
    }

    // MARK: Azioni

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
        let threshold = DateComponents(minute: thresholdMinutes)
        let event: DeviceActivityEvent
        if #available(iOS 17.4, *) {
            event = DeviceActivityEvent(applications: selection.applicationTokens,
                                        categories: selection.categoryTokens,
                                        webDomains: selection.webDomainTokens,
                                        threshold: threshold,
                                        includesPastActivity: includesPastActivity)
        } else {
            event = DeviceActivityEvent(applications: selection.applicationTokens,
                                        categories: selection.categoryTokens,
                                        webDomains: selection.webDomainTokens,
                                        threshold: threshold)
        }
        do {
            // Sovrascrive eventuale schedule/eventi precedenti con lo stesso nome.
            try center.startMonitoring(.daily, during: schedule, events: [.threshold: event])
            settings.activeThresholdMinutes = thresholdMinutes
            if settings.monitoringStartDay == nil {
                settings.monitoringStartDay = DayKey.string(from: Date())
            }
            appLog("monitor.start", "soglia \(thresholdMinutes) min, \(selectionSummary), includesPastActivity=\(includesPastActivity)")
        } catch {
            appLog("monitor.error", String(describing: error))
        }
        refresh()
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

    // MARK: Coppia

    func createCoupleAndInvite() async {
        await busy {
            let (zoneID, share) = try await self.cloud.createZoneAndShare()
            self.setCouple(role: .owner, zoneID: zoneID)
            self.appLog("couple.owner", "zona \(zoneID.zoneName) creata, share \(share.recordID.recordName)")
            self.presentSharingController(share)
        }
    }

    func copyPublicLink() async {
        await busy {
            guard let zoneID = self.zoneID else { throw CloudSyncError.noCouple }
            let existing = try await self.cloud.fetchShare(zoneID: zoneID)
            let share = try await self.cloud.makePublicReadWrite(existing)
            if let url = share.url {
                UIPasteboard.general.url = url
                self.appLog("sharing", "link pubblico copiato: \(url.absoluteString)")
            } else {
                self.appLog("sharing", "share senza URL")
            }
        }
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        await busy {
            let zoneID = try await self.cloud.accept(metadata)
            self.setCouple(role: .participant, zoneID: zoneID)
            self.appLog("couple.participant", "accettato share di \(zoneID.ownerName)")
        }
        await syncNow(reason: "accept")
    }

    func discoverSharedZone() async {
        await busy {
            let zoneID = try await self.cloud.discoverSharedZone()
            self.setCouple(role: .participant, zoneID: zoneID)
            self.appLog("couple.participant", "zona trovata nel DB condiviso, owner \(zoneID.ownerName)")
        }
    }

    func resetCoupleLocally() {
        settings.role = CoupleRole.none.rawValue
        settings.zoneName = nil
        settings.zoneOwnerName = nil
        role = .none
        cloudResults = []
        appLog("couple.reset")
    }

    private func setCouple(role: CoupleRole, zoneID: CKRecordZone.ID) {
        settings.role = role.rawValue
        settings.zoneName = zoneID.zoneName
        settings.zoneOwnerName = zoneID.ownerName
        self.role = role
    }

    private func presentSharingController(_ share: CKShare) {
        guard let top = UIApplication.shared.topViewController else {
            appLog("sharing", "nessun view controller per presentare UICloudSharingController")
            return
        }
        let controller = UICloudSharingController(share: share, container: cloud.container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = sharingDelegate
        top.present(controller, animated: true)
    }

    // MARK: Sync

    /// Pubblica i DayResult locali e scarica quelli di entrambi. Usata in foreground, da push e da BGAppRefresh.
    @discardableResult
    func syncNow(reason: String) async -> Bool {
        refresh()
        do {
            if userId == nil {
                let id = try await cloud.fetchUserId()
                userId = id
                settings.userId = id
            }
            guard role != .none, let zoneID else {
                lastSyncDescription = "\(Self.timeString(Date())) (\(reason)): nessuna coppia"
                return true
            }
            let mine = localResults
            try await cloud.save(mine, role: role, zoneID: zoneID)
            cloudResults = try await cloud.fetchAll(role: role, zoneID: zoneID)
                .sorted { ($0.date, $0.userId) > ($1.date, $1.userId) }
            try? await cloud.ensureSubscription(role: role)
            if role == .owner, let share = try? await cloud.fetchShare(zoneID: zoneID) {
                participantsDescription = Self.describe(share)
            }
            lastError = nil
            lastSyncDescription = "\(Self.timeString(Date())) (\(reason)): inviati \(mine.count), ricevuti \(cloudResults.count)"
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

    private static func describe(_ share: CKShare) -> String {
        share.participants.map { p in
            let name = p.userIdentity.nameComponents.map {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
            } ?? p.userIdentity.userRecordID?.recordName ?? "?"
            let status: String
            switch p.acceptanceStatus {
            case .accepted: status = "accepted"
            case .pending: status = "pending"
            case .removed: status = "removed"
            default: status = "unknown"
            }
            let isOwner = p.role == .owner ? " [owner]" : ""
            return "\(name): \(status)\(isOwner)"
        }.joined(separator: "\n")
    }

    static func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}

// MARK: - UIKit helpers

final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
    var onEvent: ((String) -> Void)?

    func cloudSharingController(_ csc: UICloudSharingController,
                                failedToSaveShareWithError error: Error) {
        onEvent?("failedToSaveShare: \(error)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { "Duo Spike" }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        onEvent?("didSaveShare")
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        onEvent?("didStopSharing")
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
