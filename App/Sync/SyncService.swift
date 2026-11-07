import Foundation

/// Membro di una coppia.
struct PairMember: Codable, Hashable {
    var userId: String
    var displayName: String
}

/// Coppia attiva (sempre 2 membri, incluso l'utente corrente).
struct Pairing: Codable, Hashable {
    var pairId: String
    var members: [PairMember]

    func partner(of userId: String) -> PairMember? { members.first { $0.userId != userId } }
}

/// Invito da mandare al partner (codice da digitare o da inserire in un link).
struct Invite: Hashable {
    var code: String
    var expiresAt: Date?
}

/// Confine tra la parte Screen Time (solo iOS, nativa) e il backend (da scegliere, condiviso con Android).
///
/// Contratto che un backend reale deve rispettare:
/// - `upload` e' un upsert **idempotente** sulla chiave (userId, date): l'app lo richiama piu' volte
///   (foreground, BGAppRefresh, retry) ricalcolando i risultati dal log locale, senza coda di invio.
/// - il server accetta in scrittura solo i DayResult dell'utente autenticato.
/// - `fetchPairResults` restituisce i DayResult di entrambi i membri della coppia.
/// - per avvisare il partner in tempo reale servira' una push (APNs/FCM) inviata dal backend:
///   e' fuori da questa interfaccia e da questo spike.
///
/// `@MainActor` per semplicita' nello spike: le implementazioni reali fanno la rete con `await`.
@MainActor
protocol SyncService: AnyObject {
    /// Nome mostrato nella schermata debug.
    var backendName: String { get }

    /// ID stabile dell'utente sul backend (crea l'utente se serve, es. login anonimo).
    func currentUserId() async throws -> String

    /// Coppia attiva, se esiste.
    func pairing() async throws -> Pairing?

    /// Crea un invito per il partner.
    func createInvite(displayName: String) async throws -> Invite

    /// Entra nella coppia con il codice ricevuto dal partner.
    func acceptInvite(code: String, displayName: String) async throws -> Pairing

    /// Esce dalla coppia.
    func leavePair() async throws

    /// Upsert dei risultati dell'utente corrente.
    func upload(_ results: [DayResult]) async throws

    /// Risultati di entrambi i membri della coppia negli ultimi `days` giorni.
    func fetchPairResults(days: Int) async throws -> [DayResult]
}

enum SyncError: LocalizedError {
    case offline
    case notPaired
    case invalidInvite
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case .offline: return "Backend non raggiungibile (simulato)."
        case .notPaired: return "Nessuna coppia attiva."
        case .invalidInvite: return "Codice invito non valido."
        case .forbidden(let detail): return "Scrittura rifiutata: \(detail)"
        }
    }
}
