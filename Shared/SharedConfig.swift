import Foundation
import DeviceActivity

/// Identificatori condivisi tra app ed estensione. App Group e container arrivano da
/// Config/Base.xcconfig tramite le chiavi custom dell'Info.plist di ciascun target.
enum SharedConfig {
    static let appGroupID: String =
        Bundle.main.object(forInfoDictionaryKey: "DuoAppGroupID") as? String ?? "group.invalid"
    static let containerID: String =
        Bundle.main.object(forInfoDictionaryKey: "DuoCloudKitContainerID") as? String ?? "iCloud.invalid"

    static let zoneName = "DuoZone"
    static let recordType = "DayResult"
}

extension DeviceActivityName {
    /// Unica attivita': finestra giornaliera 00:00-23:59 che si ripete.
    static let daily = Self("duo.daily")
}

extension DeviceActivityEvent.Name {
    static let threshold = Self("duo.threshold")
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
}

/// Contenitore per valori mutati da closure @Sendable (callback di URLSession/CloudKit).
final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
