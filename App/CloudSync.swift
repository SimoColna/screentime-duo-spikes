import CloudKit
import Foundation

enum CoupleRole: String {
    /// Nessuna coppia configurata.
    case none
    /// Ha creato la zona `DuoZone` nel proprio database privato e il CKShare zone-wide.
    case owner
    /// Ha accettato il CKShare: vede la zona nel proprio database condiviso.
    case participant
}

enum CloudSyncError: LocalizedError {
    case noCouple
    case shareMissing
    case noSharedZone

    var errorDescription: String? {
        switch self {
        case .noCouple: return "Coppia non configurata."
        case .shareMissing: return "CKShare non trovato nella zona."
        case .noSharedZone: return "Nessuna zona \(SharedConfig.zoneName) nel database condiviso: l'invito e' stato accettato?"
        }
    }
}

/// Tutte le chiamate CloudKit. Modello dati:
/// - una sola zona custom `DuoZone` nel database privato del proprietario, condivisa con CKShare(recordZoneID:)
/// - entrambi scrivono i propri DayResult in quella zona (owner: privateDB, participant: sharedDB)
final class CloudSync {
    let container = CKContainer(identifier: SharedConfig.containerID)

    func database(for role: CoupleRole) -> CKDatabase? {
        switch role {
        case .owner: return container.privateCloudDatabase
        case .participant: return container.sharedCloudDatabase
        case .none: return nil
        }
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    func fetchUserId() async throws -> String {
        try await container.userRecordID().recordName
    }

    // MARK: Owner

    /// Crea (idempotente) la zona e il CKShare zone-wide. Restituisce lo share salvato.
    func createZoneAndShare() async throws -> (CKRecordZone.ID, CKShare) {
        let db = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: SharedConfig.zoneName)
        let (zoneResults, _) = try await db.modifyRecordZones(saving: [zone], deleting: [])
        for result in zoneResults.values { _ = try result.get() }

        if let existing = try? await fetchShare(zoneID: zone.zoneID) {
            return (zone.zoneID, existing)
        }

        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = "Duo Spike" as NSString
        share.publicPermission = .none
        let saved = try await save(share: share)
        return (zone.zoneID, saved)
    }

    func fetchShare(zoneID: CKRecordZone.ID) async throws -> CKShare {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        let record = try await container.privateCloudDatabase.record(for: id)
        guard let share = record as? CKShare else { throw CloudSyncError.shareMissing }
        return share
    }

    /// Fallback all'invito tramite UICloudSharingController: link pubblico read/write.
    func makePublicReadWrite(_ share: CKShare) async throws -> CKShare {
        share.publicPermission = .readWrite
        return try await save(share: share)
    }

    private func save(share: CKShare) async throws -> CKShare {
        let (results, _) = try await container.privateCloudDatabase
            .modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
        guard let result = results[share.recordID] else { throw CloudSyncError.shareMissing }
        return (try result.get() as? CKShare) ?? share
    }

    // MARK: Participant

    func accept(_ metadata: CKShare.Metadata) async throws -> CKRecordZone.ID {
        _ = try await container.accept(metadata)
        return metadata.share.recordID.zoneID
    }

    /// Recupero manuale se l'accettazione via SceneDelegate non e' arrivata all'app.
    func discoverSharedZone() async throws -> CKRecordZone.ID {
        let zones = try await container.sharedCloudDatabase.allRecordZones()
        guard let zone = zones.first(where: { $0.zoneID.zoneName == SharedConfig.zoneName }) else {
            throw CloudSyncError.noSharedZone
        }
        return zone.zoneID
    }

    // MARK: Dati

    func save(_ results: [DayResult], role: CoupleRole, zoneID: CKRecordZone.ID) async throws {
        guard let db = database(for: role) else { throw CloudSyncError.noCouple }
        guard !results.isEmpty else { return }
        let records = results.map { $0.toRecord(zoneID: zoneID) }
        let (saveResults, _) = try await db.modifyRecords(saving: records, deleting: [],
                                                          savePolicy: .allKeys, atomically: false)
        for result in saveResults.values { _ = try result.get() }
    }

    /// Scarica tutti i record della zona (dataset minuscolo: niente change token nello spike).
    /// Si usa CKFetchRecordZoneChangesOperation invece di CKQuery per non dover creare indici queryable.
    func fetchAll(role: CoupleRole, zoneID: CKRecordZone.ID) async throws -> [DayResult] {
        guard let db = database(for: role) else { throw CloudSyncError.noCouple }
        let records = Box<[CKRecord]>([])
        return try await withCheckedThrowingContinuation { continuation in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = nil
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID],
                                                              configurationsByRecordZoneID: [zoneID: config])
            operation.fetchAllChanges = true
            operation.qualityOfService = .userInitiated
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result { records.value.append(record) }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records.value.compactMap(DayResult.init(record:)))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            db.add(operation)
        }
    }

    /// Push silenziosa quando cambia qualcosa nel database (owner: privato, participant: condiviso).
    func ensureSubscription(role: CoupleRole) async throws {
        guard let db = database(for: role) else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: "duo-db-\(role.rawValue)")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        let (results, _) = try await db.modifySubscriptions(saving: [subscription], deleting: [])
        for result in results.values { _ = try result.get() }
    }
}
