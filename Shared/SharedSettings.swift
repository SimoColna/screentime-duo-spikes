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
        static let activeLadder = "activeLadderPercents"
        static let includesPast = "includesPastActivity"
        static let monitoringStartDay = "monitoringStartDay"
        static let displayName = "displayName"
        static let userId = "userId"
        static let probeNetwork = "probeNetwork"
        static let probeURL = "probeURL"
        static let probeNotification = "probeNotification"
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

    /// Gradini (percentuali) effettivamente registrati con l'ultimo startMonitoring.
    var activeLadderPercents: [Int] {
        get { defaults.array(forKey: Key.activeLadder) as? [Int] ?? [] }
        set { defaults.set(newValue, forKey: Key.activeLadder) }
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

    /// ID utente restituito dal SyncService (serve all'estensione per il body della probe di rete).
    var userId: String? {
        get { defaults.string(forKey: Key.userId) }
        set { defaults.set(newValue, forKey: Key.userId) }
    }

    /// Esperimento domanda 2: l'estensione prova una richiesta HTTPS.
    var probeNetwork: Bool {
        get { defaults.bool(forKey: Key.probeNetwork) }
        set { defaults.set(newValue, forKey: Key.probeNetwork) }
    }

    /// Vuoto = GET alla pagina di test Apple. Altrimenti POST JSON del DayResult a questo URL
    /// (es. un endpoint di test tipo webhook) per simulare la scrittura su un backend.
    var probeURL: String {
        get { defaults.string(forKey: Key.probeURL) ?? "" }
        set { defaults.set(newValue, forKey: Key.probeURL) }
    }

    /// Esperimento domanda 2: l'estensione pubblica una notifica locale.
    var probeNotification: Bool {
        get { defaults.bool(forKey: Key.probeNotification) }
        set { defaults.set(newValue, forKey: Key.probeNotification) }
    }
}
