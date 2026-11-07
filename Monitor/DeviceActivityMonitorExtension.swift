import DeviceActivity
import Foundation

/// Estensione DeviceActivityMonitor: deve restare leggera (limite memoria ~6 MB) e ogni override
/// deve tornare in fretta: il ciclo di vita finisce quando il metodo sincrono ritorna.
/// Strategia principale: scrivere SOLO nel log dell'App Group; l'app principale sincronizza
/// tramite SyncService (backend ancora da scegliere).
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let settings = SharedSettings()

    override init() {
        super.init()
        // Utile per capire quante volte il sistema lancia il processo (es. dopo riavvio).
        log(LogKind.extensionInit)
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        log(LogKind.intervalDidStart, activity.rawValue)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        log(LogKind.intervalDidEnd, activity.rawValue)
    }

    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name,
                                                 activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        log(LogKind.thresholdWarning, "\(activity.rawValue)/\(event.rawValue)")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let now = Date()

        if let percent = event.ladderPercent {
            // Gradino intermedio: serve solo alla diagnosi dei falsi positivi.
            log(LogKind.ladderReached, "\(percent)%", at: now)
            return
        }
        guard event == .threshold else {
            log(LogKind.unknownEvent, "\(activity.rawValue)/\(event.rawValue)", at: now)
            return
        }

        // 1) Fonte di verita': evento nel log dell'App Group (poi letto dall'app).
        log(LogKind.thresholdReached, "\(activity.rawValue)/\(event.rawValue)", at: now)

        // 2) Esperimenti opzionali per la domanda 2 (attivabili dalla schermata debug).
        if settings.probeNotification {
            Probes.notification(settings: settings)
        }
        if settings.probeNetwork {
            Probes.network(settings: settings, at: now)
        }
    }

    private func log(_ kind: String, _ detail: String = "", at date: Date = Date()) {
        EventLog.append(LogEntry(source: "ext", kind: kind, detail: detail,
                                 threshold: settings.activeThresholdMinutes, at: date))
    }
}
