import Foundation

/// Backend finto, tutto in locale (UserDefaults dell'app). Serve a esercitare il flusso
/// "estensione -> App Group -> app -> SyncService" senza scegliere ancora il backend.
///
/// Il partner e' simulato: l'invito viene "accettato" subito da un utente finto, e i suoi
/// DayResult si impostano dalla schermata debug (`simulatePartner`). Si possono simulare anche
/// latenza e backend offline per verificare che il sync ricalcolato dal log sia idempotente.
@MainActor
final class LocalFakeSyncService: SyncService {
    static let partnerId = "fake-partner"
    static let partnerName = "Partner simulato"

    let backendName = "Fake locale (UserDefaults)"
    var isOffline = false
    var latency: TimeInterval = 0.3

    private struct State: Codable {
        var userId: String
        var pairing: Pairing?
        var results: [String: DayResult]
    }

    private let defaults = UserDefaults.standard
    private let key = "fakeBackend.v1"

    // MARK: SyncService

    func currentUserId() async throws -> String {
        try await simulateNetwork()
        return load().userId
    }

    func pairing() async throws -> Pairing? {
        try await simulateNetwork()
        return load().pairing
    }

    func createInvite(displayName: String) async throws -> Invite {
        try await simulateNetwork()
        var state = load()
        let code = "DUO-" + String(Int.random(in: 1000...9999))
        // Simulazione: il partner accetta subito.
        state.pairing = Pairing(pairId: UUID().uuidString, members: [
            PairMember(userId: state.userId, displayName: displayName),
            PairMember(userId: Self.partnerId, displayName: Self.partnerName),
        ])
        save(state)
        return Invite(code: code, expiresAt: Date().addingTimeInterval(24 * 3600))
    }

    func acceptInvite(code: String, displayName: String) async throws -> Pairing {
        try await simulateNetwork()
        guard code.trimmingCharacters(in: .whitespaces).count >= 4 else { throw SyncError.invalidInvite }
        var state = load()
        let pairing = Pairing(pairId: UUID().uuidString, members: [
            PairMember(userId: Self.partnerId, displayName: Self.partnerName),
            PairMember(userId: state.userId, displayName: displayName),
        ])
        state.pairing = pairing
        save(state)
        return pairing
    }

    func leavePair() async throws {
        try await simulateNetwork()
        var state = load()
        state.pairing = nil
        save(state)
    }

    func upload(_ results: [DayResult]) async throws {
        try await simulateNetwork()
        var state = load()
        guard state.pairing != nil else { throw SyncError.notPaired }
        for var result in results {
            // Come farebbe un backend reale: si scrivono solo i propri record.
            guard result.userId == state.userId else {
                throw SyncError.forbidden("userId \(result.userId) diverso dall'utente autenticato")
            }
            result.updatedAt = Date()
            state.results[result.id] = result
        }
        save(state)
    }

    func fetchPairResults(days: Int) async throws -> [DayResult] {
        try await simulateNetwork()
        let state = load()
        guard let pairing = state.pairing else { throw SyncError.notPaired }
        let members = Set(pairing.members.map(\.userId))
        let cutoff = DayKey.string(daysAgo: max(days - 1, 0))
        return state.results.values
            .filter { members.contains($0.userId) && $0.date >= cutoff }
            .sorted { ($0.date, $0.userId) > ($1.date, $1.userId) }
    }

    // MARK: Solo debug

    /// Imposta lo stato del partner simulato per un giorno.
    func simulatePartner(day: String, exceeded: Bool, threshold: Int) {
        var state = load()
        let now = Date()
        let result = DayResult(date: day, userId: Self.partnerId, threshold: threshold,
                               exceeded: exceeded, exceededAt: exceeded ? now : nil,
                               displayName: Self.partnerName, updatedAt: now)
        state.results[result.id] = result
        save(state)
    }

    /// Cancella tutto il "server" finto (utente, coppia, risultati).
    func wipe() {
        defaults.removeObject(forKey: key)
    }

    // MARK: Persistenza

    private func simulateNetwork() async throws {
        if latency > 0 {
            try await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000))
        }
        if isOffline { throw SyncError.offline }
    }

    private func load() -> State {
        if let data = defaults.data(forKey: key),
           let state = try? JSONDecoder().decode(State.self, from: data) {
            return state
        }
        let state = State(userId: "local-" + UUID().uuidString.prefix(8).lowercased(),
                          pairing: nil, results: [:])
        save(state)
        return state
    }

    private func save(_ state: State) {
        defaults.set(try? JSONEncoder().encode(state), forKey: key)
    }
}
