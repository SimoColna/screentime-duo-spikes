import Foundation

/// Impostazioni nell'App Group (UserDefaults condivisi). L'app scrive, l'estensione legge.
final class SharedSettings {
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: SharedConfig.appGroupID) ?? .standard
    }

    private enum Key {
        static let selection = "selection"
        static let threshold = "thresholdMinutes"
        static let activeThreshold = "activeThresholdMinutes"
        static let includesPast = "includesPastActivity"
        static let monitoringStartDay = "monitoringStartDay"
        static let displayName = "displayName"
        static let probeNetwork = "probeNetwork"
        static let probeCloudKit = "probeCloudKit"
        static let role = "coupleRole"
        static let zoneName = "zoneName"
        static let zoneOwner = "zoneOwnerName"
        static let userId = "userId"
    }

    /// FamilyActivitySelection codificata in JSON (la codifica avviene nell'app).
    var selectionData: Data? {
        get { defaults.data(forKey: Key.selection) }
        set { defaults.set(newValue, forKey: Key.selection) }
    }

    /// Soglia scelta nella UI.
    var thresholdMinutes: Int {
        get { let v = defaults.integer(forKey: Key.threshold); return v == 0 ? 15 : v }
        set { defaults.set(newValue, forKey: Key.threshold) }
    }

    /// Soglia effettivamente passata a startMonitoring (puo' differire dalla UI finche' non si riavvia).
    var activeThresholdMinutes: Int? {
        get { defaults.object(forKey: Key.activeThreshold) as? Int }
        set { defaults.set(newValue, forKey: Key.activeThreshold) }
    }

    var includesPastActivity: Bool {
        get { defaults.object(forKey: Key.includesPast) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.includesPast) }
    }

    /// Primo giorno (yyyy-MM-dd) in cui il monitor e' stato avviato: prima di questo non si pubblicano DayResult.
    var monitoringStartDay: String? {
        get { defaults.string(forKey: Key.monitoringStartDay) }
        set { defaults.set(newValue, forKey: Key.monitoringStartDay) }
    }

    var displayName: String {
        get { defaults.string(forKey: Key.displayName) ?? "" }
        set { defaults.set(newValue, forKey: Key.displayName) }
    }

    /// Esperimento domanda 2: l'estensione prova una richiesta HTTPS.
    var probeNetwork: Bool {
        get { defaults.bool(forKey: Key.probeNetwork) }
        set { defaults.set(newValue, forKey: Key.probeNetwork) }
    }

    /// Esperimento domanda 2: l'estensione prova a scrivere il DayResult su CloudKit.
    var probeCloudKit: Bool {
        get { defaults.bool(forKey: Key.probeCloudKit) }
        set { defaults.set(newValue, forKey: Key.probeCloudKit) }
    }

    /// "none" | "owner" | "participant"
    var role: String {
        get { defaults.string(forKey: Key.role) ?? "none" }
        set { defaults.set(newValue, forKey: Key.role) }
    }

    var zoneName: String? {
        get { defaults.string(forKey: Key.zoneName) }
        set { defaults.set(newValue, forKey: Key.zoneName) }
    }

    var zoneOwnerName: String? {
        get { defaults.string(forKey: Key.zoneOwner) }
        set { defaults.set(newValue, forKey: Key.zoneOwner) }
    }

    /// recordName del CKUserRecord dell'utente in questo container.
    var userId: String? {
        get { defaults.string(forKey: Key.userId) }
        set { defaults.set(newValue, forKey: Key.userId) }
    }
}
