import Foundation

/// Record minimo condiviso col partner: DayResult {date, userId, threshold, exceeded}
/// (+ exceededAt/displayName/updatedAt per il debug della latenza).
/// Codable e indipendente dal backend: lo stesso JSON potra' essere letto dall'app Android.
struct DayResult: Codable, Identifiable, Hashable {
    /// Giorno locale dell'utente, yyyy-MM-dd.
    var date: String
    var userId: String
    /// Minuti.
    var threshold: Int
    var exceeded: Bool
    var exceededAt: Date?
    var displayName: String?
    var updatedAt: Date?

    /// Chiave naturale per l'upsert idempotente: un record per utente per giorno.
    var id: String { "\(userId)_\(date)" }

    /// Ricava i risultati degli ultimi `days` giorni dal log locale.
    /// Un giorno e' "exceeded" se esiste almeno un eventDidReachThreshold (evento soglia, non gradino)
    /// con quel giorno. Il giorno corrente senza evento e' "non superata (finora)".
    static func local(from log: [LogEntry], userId: String, displayName: String?,
                      currentThreshold: Int, startDay: String?,
                      today: Date = Date(), days: Int = 7) -> [DayResult] {
        guard let startDay else { return [] }
        var out: [DayResult] = []
        for offset in 0..<days {
            let key = DayKey.string(daysAgo: offset, from: today)
            if key < startDay { break }
            let hit = log.first { $0.kind == LogKind.thresholdReached && $0.day == key }
            out.append(DayResult(date: key, userId: userId,
                                 threshold: hit?.threshold ?? currentThreshold,
                                 exceeded: hit != nil, exceededAt: hit?.at,
                                 displayName: displayName))
        }
        return out
    }
}
