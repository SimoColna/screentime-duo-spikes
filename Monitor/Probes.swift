import CloudKit
import Foundation

/// Esperimenti per la domanda 2: l'estensione puo' fare rete / scrivere su CloudKit?
/// Ogni probe scrive un evento ".start" PRIMA e uno con l'esito DOPO: se nel log c'e' solo
/// lo start, il processo e' stato terminato (o e' andato in jetsam) prima di finire.
/// Si blocca il thread con un semaforo perche' DeviceActivityMonitor non ha callback async.
enum Probes {
    static func network(settings: SharedSettings) {
        log(LogKind.probeNetwork + ".start", "", settings)
        let started = Date()
        let outcome = Box("timeout")
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                outcome.value = "error: \(error.localizedDescription)"
            } else {
                outcome.value = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 5)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        log(LogKind.probeNetwork, "\(outcome.value) in \(ms) ms", settings)
    }

    static func cloudKit(settings: SharedSettings, at date: Date) {
        guard let userId = settings.userId,
              let zoneName = settings.zoneName,
              let owner = settings.zoneOwnerName,
              settings.role != "none" else {
            log(LogKind.probeCloudKit, "skip: coppia/userId non configurati nell'app", settings)
            return
        }
        log(LogKind.probeCloudKit + ".start", "", settings)
        let started = Date()

        let container = CKContainer(identifier: SharedConfig.containerID)
        let database = settings.role == "owner" ? container.privateCloudDatabase
                                                : container.sharedCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: owner)
        let result = DayResult(date: DayKey.string(from: date), userId: userId,
                               threshold: settings.activeThresholdMinutes ?? settings.thresholdMinutes,
                               exceeded: true, exceededAt: date,
                               displayName: settings.displayName + " (ext)")

        let outcome = Box("timeout")
        let semaphore = DispatchSemaphore(value: 0)
        let operation = CKModifyRecordsOperation(recordsToSave: [result.toRecord(zoneID: zoneID)],
                                                 recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.qualityOfService = .userInitiated
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success: outcome.value = "ok"
            case .failure(let error): outcome.value = "error: \(error)"
            }
            semaphore.signal()
        }
        database.add(operation)

        _ = semaphore.wait(timeout: .now() + 8)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        log(LogKind.probeCloudKit, "\(outcome.value) in \(ms) ms", settings)
    }

    private static func log(_ kind: String, _ detail: String, _ settings: SharedSettings) {
        EventLog.append(LogEntry(source: "ext", kind: kind, detail: detail,
                                 threshold: settings.activeThresholdMinutes))
    }
}
