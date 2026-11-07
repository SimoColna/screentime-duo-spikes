import Foundation
import CloudKit

/// Record minimo condiviso: DayResult {date, userId, threshold, exceeded}
/// (+ exceededAt/displayName/updatedAt per il debug della latenza).
struct DayResult: Identifiable, Hashable {
    var date: String
    var userId: String
    var threshold: Int
    var exceeded: Bool
    var exceededAt: Date?
    var displayName: String?
    var updatedAt: Date?

    /// Record ID deterministico: un record per utente per giorno, upsert senza query.
    var id: String { "\(userId)_\(date)" }

    func toRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: SharedConfig.recordType,
                              recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
        record["date"] = date as NSString
        record["userId"] = userId as NSString
        record["threshold"] = NSNumber(value: threshold)
        record["exceeded"] = NSNumber(value: exceeded)
        record["exceededAt"] = exceededAt.map { $0 as NSDate }
        record["displayName"] = displayName.map { $0 as NSString }
        record["updatedAt"] = Date() as NSDate
        return record
    }

    init(date: String, userId: String, threshold: Int, exceeded: Bool,
         exceededAt: Date? = nil, displayName: String? = nil, updatedAt: Date? = nil) {
        self.date = date
        self.userId = userId
        self.threshold = threshold
        self.exceeded = exceeded
        self.exceededAt = exceededAt
        self.displayName = displayName
        self.updatedAt = updatedAt
    }

    init?(record: CKRecord) {
        guard record.recordType == SharedConfig.recordType,
              let date = record["date"] as? String,
              let userId = record["userId"] as? String else { return nil }
        self.date = date
        self.userId = userId
        self.threshold = (record["threshold"] as? NSNumber)?.intValue ?? 0
        self.exceeded = (record["exceeded"] as? NSNumber)?.boolValue ?? false
        self.exceededAt = record["exceededAt"] as? Date
        self.displayName = record["displayName"] as? String
        self.updatedAt = (record["updatedAt"] as? Date) ?? record.modificationDate
    }

    /// Ricava i risultati degli ultimi `days` giorni dal log locale.
    /// Un giorno e' "exceeded" se esiste almeno un eventDidReachThreshold con quel giorno.
    /// Il giorno corrente senza evento e' "non superata (finora)".
    static func local(from log: [LogEntry], userId: String, displayName: String?,
                      currentThreshold: Int, startDay: String?,
                      today: Date = Date(), days: Int = 7) -> [DayResult] {
        guard let startDay else { return [] }
        let calendar = Calendar.current
        var out: [DayResult] = []
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = DayKey.string(from: date)
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
