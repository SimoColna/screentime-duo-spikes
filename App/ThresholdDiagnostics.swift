import Foundation

/// Diagnosi automatica dei falsi positivi (domanda 1).
///
/// Oltre all'evento soglia (N minuti), il monitor registra eventi "gradino" a 25/50/75% di N.
/// Con uso reale i gradini arrivano in ordine e prima della soglia, e tra il primo gradino
/// (m minuti) e la soglia devono passare almeno (N - m) minuti di orologio.
/// Una soglia senza gradini precedenti, o troppo vicina al primo gradino, e' fisicamente
/// impossibile, quindi sospetta. Dentro 2 minuti da un `monitor.start` la verifica non vale:
/// con includesPastActivity tutti gli eventi possono scattare insieme legittimamente.
enum ThresholdDiagnostics {
    struct Step: Hashable {
        let percent: Int
        let minutes: Int
    }

    enum Verdict: Hashable {
        case noEvent
        case plausible
        case suspicious(String)
        case notAssessable(String)

        var label: String {
            switch self {
            case .noEvent: return "nessuna soglia"
            case .plausible: return "plausibile"
            case .suspicious: return "SOSPETTO"
            case .notAssessable: return "non valutabile"
            }
        }

        var reason: String? {
            switch self {
            case .suspicious(let r), .notAssessable(let r): return r
            default: return nil
            }
        }
    }

    struct Day: Identifiable, Hashable {
        let day: String
        let thresholdMinutes: Int?
        let thresholdAt: Date?
        /// Quante volte e' arrivato eventDidReachThreshold per la soglia (duplicati > 1).
        let thresholdCount: Int
        /// Primo arrivo di ciascun gradino (percentuale -> data).
        let ladder: [Int: Date]
        let verdict: Verdict
        var id: String { day }
    }

    /// Gradini registrabili per una soglia: solo minuti interi >= 1, distinti e < soglia.
    static func steps(for threshold: Int) -> [Step] {
        var seen = Set<Int>()
        var out: [Step] = []
        for percent in SharedConfig.ladderPercents {
            let minutes = threshold * percent / 100
            if minutes >= 1, minutes < threshold, seen.insert(minutes).inserted {
                out.append(Step(percent: percent, minutes: minutes))
            }
        }
        return out
    }

    static func diagnose(log: [LogEntry], days: Int = 7, today: Date = Date()) -> [Day] {
        let monitorStarts = log.filter { $0.kind == LogKind.monitorStart }.map(\.at)
        return (0..<days).map { offset in
            diagnose(day: DayKey.string(daysAgo: offset, from: today), log: log, monitorStarts: monitorStarts)
        }
    }

    private static func diagnose(day: String, log: [LogEntry], monitorStarts: [Date]) -> Day {
        let entries = log.filter { $0.day == day }
        let thresholds = entries.filter { $0.kind == LogKind.thresholdReached }.sorted { $0.at < $1.at }
        var ladder: [Int: Date] = [:]
        for entry in entries where entry.kind == LogKind.ladderReached {
            guard let percent = Int(entry.detail.replacingOccurrences(of: "%", with: "")) else { continue }
            if ladder[percent].map({ entry.at < $0 }) ?? true { ladder[percent] = entry.at }
        }

        guard let first = thresholds.first else {
            return Day(day: day, thresholdMinutes: nil, thresholdAt: nil, thresholdCount: 0,
                       ladder: ladder, verdict: .noEvent)
        }
        let minutes = first.threshold ?? 0
        let verdict: Verdict

        if monitorStarts.contains(where: { (0...120).contains(first.at.timeIntervalSince($0)) }) {
            verdict = .notAssessable("soglia entro 2 min da monitor.start")
        } else {
            let expected = steps(for: minutes)
            let missing = expected.filter { step in
                guard let at = ladder[step.percent] else { return true }
                return at > first.at
            }
            if !missing.isEmpty {
                verdict = .suspicious("mancano i gradini \(missing.map { "\($0.percent)%" }.joined(separator: ", ")) prima della soglia")
            } else if let firstStep = expected.first, let stepAt = ladder[firstStep.percent] {
                let minGap = Double(minutes - firstStep.minutes) * 60
                let gap = first.at.timeIntervalSince(stepAt)
                // 30 s di tolleranza sui tempi di consegna dei callback.
                verdict = gap + 30 < minGap
                    ? .suspicious("soglia \(Int(gap)) s dopo il gradino \(firstStep.percent)%, servono almeno \(Int(minGap)) s di uso")
                    : .plausible
            } else {
                verdict = .notAssessable("soglia < 4 min: nessun gradino registrabile")
            }
        }
        return Day(day: day, thresholdMinutes: minutes, thresholdAt: first.at,
                   thresholdCount: thresholds.count, ladder: ladder, verdict: verdict)
    }
}
