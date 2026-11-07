import DeviceActivity
import Foundation

/// Identificatori condivisi tra app ed estensione. L'App Group arriva da Config/Base.xcconfig
/// tramite la chiave custom `DuoAppGroupID` nell'Info.plist di ciascun target.
enum SharedConfig {
    static let appGroupID: String =
        Bundle.main.object(forInfoDictionaryKey: "DuoAppGroupID") as? String ?? "group.invalid"

    /// Gradini intermedi (percentuale della soglia) registrati come eventi aggiuntivi
    /// per riconoscere i falsi positivi (domanda 1). Vedi ThresholdDiagnostics.
    static let ladderPercents = [25, 50, 75]
}

extension DeviceActivityName {
    /// Unica attivita': finestra giornaliera 00:00-23:59 che si ripete.
    static let daily = Self("duo.daily")
}

extension DeviceActivityEvent.Name {
    static let threshold = Self("duo.threshold")

    private static let ladderPrefix = "duo.ladder."

    static func ladder(_ percent: Int) -> Self { Self(ladderPrefix + String(percent)) }

    /// Percentuale se e' un evento "gradino", altrimenti nil.
    var ladderPercent: Int? {
        guard rawValue.hasPrefix(Self.ladderPrefix) else { return nil }
        return Int(rawValue.dropFirst(Self.ladderPrefix.count))
    }
}

/// Chiave del giorno nel fuso orario locale del telefono, formato yyyy-MM-dd.
enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }

    static func string(daysAgo: Int, from date: Date = Date()) -> String {
        string(from: Calendar.current.date(byAdding: .day, value: -daysAgo, to: date) ?? date)
    }
}

/// Contenitore per valori mutati da closure @Sendable (callback di URLSession ecc.).
final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
