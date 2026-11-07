import Foundation
import UserNotifications

/// Esperimenti per la domanda 2, indipendenti dal backend:
/// - rete: l'estensione riesce a completare una richiesta HTTPS (GET di test o POST del DayResult)?
/// - notifica locale: l'estensione puo' avvisare l'utente e invitarlo ad aprire l'app (che poi sincronizza)?
/// Ogni probe scrive un evento ".start" PRIMA e uno con l'esito DOPO: se nel log c'e' solo
/// lo start, il processo e' stato terminato (o e' andato in jetsam) prima di finire.
/// Si blocca il thread con un semaforo perche' DeviceActivityMonitor non ha callback async
/// (workaround suggerito da Apple nel thread 724649, con timeout di pochi secondi).
enum Probes {
    static let defaultURL = URL(string: "https://www.apple.com/library/test/success.html")!

    static func network(settings: SharedSettings, at date: Date) {
        let custom = URL(string: settings.probeURL.trimmingCharacters(in: .whitespaces))
        var request = URLRequest(url: custom ?? defaultURL)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if custom != nil {
            // Simula la scrittura su un backend: POST del DayResult in JSON.
            let result = DayResult(date: DayKey.string(from: date),
                                   userId: settings.userId ?? "unknown",
                                   threshold: settings.activeThresholdMinutes ?? settings.thresholdMinutes,
                                   exceeded: true, exceededAt: date,
                                   displayName: settings.displayName, updatedAt: date)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? encoder.encode(result)
        }

        log(LogKind.probeNetwork + ".start", "\(request.httpMethod ?? "GET") \(request.url?.host ?? "?")", settings)
        let started = Date()
        let outcome = Box("timeout")
        let semaphore = DispatchSemaphore(value: 0)
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

    static func notification(settings: SharedSettings) {
        log(LogKind.probeNotification + ".start", "", settings)
        let content = UNMutableNotificationContent()
        content.title = "Soglia superata"
        content.body = "Apri Duo Spike per sincronizzare lo stato con il partner."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "duo.threshold.\(DayKey.string(from: Date()))",
                                            content: content, trigger: nil)
        let outcome = Box("timeout")
        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { error in
            outcome.value = error.map { "error: \($0.localizedDescription)" } ?? "ok"
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        log(LogKind.probeNotification, outcome.value, settings)
    }

    private static func log(_ kind: String, _ detail: String, _ settings: SharedSettings) {
        EventLog.append(LogEntry(source: "ext", kind: kind, detail: detail,
                                 threshold: settings.activeThresholdMinutes))
    }
}
