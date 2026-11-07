import Foundation

enum LogKind {
    static let extensionInit = "ext.init"
    static let intervalDidStart = "intervalDidStart"
    static let intervalDidEnd = "intervalDidEnd"
    static let thresholdWarning = "eventWillReachThresholdWarning"
    static let thresholdReached = "eventDidReachThreshold"
    static let probeNetwork = "probe.network"
    static let probeCloudKit = "probe.cloudkit"
}

struct LogEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var at: Date
    /// Giorno locale (yyyy-MM-dd) al momento della scrittura.
    var day: String
    /// "app" oppure "ext"
    var source: String
    var kind: String
    var detail: String
    /// Soglia attiva al momento dell'evento (minuti).
    var threshold: Int?

    init(source: String, kind: String, detail: String = "", threshold: Int? = nil, at: Date = Date()) {
        self.id = UUID()
        self.at = at
        self.day = DayKey.string(from: at)
        self.source = source
        self.kind = kind
        self.detail = detail
        self.threshold = threshold
    }
}

/// Log append-only in formato JSON Lines nel container dell'App Group.
/// Scelto al posto di UserDefaults per evitare read-modify-write concorrenti tra app ed estensione
/// e per tenere bassa la memoria dell'estensione (limite ~6 MB).
enum EventLog {
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupID)?
            .appendingPathComponent("events.jsonl")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func append(_ entry: LogEntry) {
        guard let url = fileURL, var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    static func readAll() -> [LogEntry] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return data
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(LogEntry.self, from: Data($0)) }
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
