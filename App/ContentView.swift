import FamilyControls
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                authorizationSection
                selectionSection
                thresholdSection
                monitorSection
                coupleSection
                todaySection
                historySection
                experimentsSection
                logSection
            }
            .navigationTitle("Duo Spike")
            .familyActivityPicker(isPresented: $showPicker, selection: $model.selection)
            .refreshable { await model.syncNow(reason: "pull") }
            .overlay { if model.isBusy { ProgressView() } }
        }
    }

    // MARK: 1-4: Screen Time

    private var authorizationSection: some View {
        Section("1. Autorizzazione Screen Time") {
            LabeledContent("Stato", value: model.authStatusText)
            Button("Richiedi autorizzazione (.individual)") {
                Task { await model.requestAuthorization() }
            }
        }
    }

    private var selectionSection: some View {
        Section("2. App social") {
            LabeledContent("Selezione", value: model.selectionSummary)
            Button("Scegli app con FamilyActivityPicker") { showPicker = true }
        }
    }

    private var thresholdSection: some View {
        Section {
            Stepper("Soglia: \(model.thresholdMinutes) min", value: $model.thresholdMinutes, in: 1...60)
            Toggle("includesPastActivity", isOn: $model.includesPastActivity)
        } header: {
            Text("3. Soglia giornaliera")
        } footer: {
            Text("Prodotto: 15-60 min. 1-14 solo per i test. includesPastActivity ha effetto da iOS 17.4. Riavvia il monitor dopo ogni modifica.")
        }
    }

    private var monitorSection: some View {
        Section("4. Monitor (00:00-23:59, ripetuto)") {
            LabeledContent("Attivita' registrate", value: model.monitoredActivities.isEmpty ? "nessuna" : model.monitoredActivities.joined(separator: ", "))
            LabeledContent("Soglia attiva", value: model.activeThresholdText)
            Button("Avvia / riavvia monitoraggio") { model.startMonitoring() }
            Button("Ferma monitoraggio", role: .destructive) { model.stopMonitoring() }
        }
    }

    // MARK: 5: Coppia

    private var coupleSection: some View {
        Section {
            LabeledContent("Ruolo", value: model.role.rawValue)
            LabeledContent("Mio userId", value: model.userId.map { String($0.suffix(12)) } ?? "-")
            TextField("Nome visualizzato", text: $model.displayName)
            switch model.role {
            case .none:
                Button("Crea coppia e invita il partner") { Task { await model.createCoupleAndInvite() } }
                Button("Ho accettato un invito: cerca la zona condivisa") { Task { await model.discoverSharedZone() } }
            case .owner:
                Button("Invita / gestisci partner") { Task { await model.createCoupleAndInvite() } }
                Button("Fallback: copia link pubblico (read/write)") { Task { await model.copyPublicLink() } }
                LabeledContent("Partecipanti") { Text(model.participantsDescription).font(.caption) }
            case .participant:
                EmptyView()
            }
            Button("Sincronizza ora") { Task { await model.syncNow(reason: "manual") } }
            LabeledContent("Ultimo sync") { Text(model.lastSyncDescription).font(.caption) }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if model.role != .none {
                Button("Reset coppia (solo locale)", role: .destructive) { model.resetCoupleLocally() }
            }
        } header: {
            Text("5. Coppia (CloudKit)")
        }
    }

    // MARK: 6: Debug

    private var todaySection: some View {
        let today = DayKey.string(from: Date())
        let localToday = model.localResults.first { $0.date == today }
        let cloudMine = model.myCloudResults.first { $0.date == today }
        let partners = model.partnerResults.filter { $0.date == today }
        return Section("6. Debug: oggi \(today)") {
            DayRow(title: "Io (log locale)", result: localToday)
            DayRow(title: "Io (copia CloudKit)", result: cloudMine)
            if partners.isEmpty {
                DayRow(title: "Partner (CloudKit)", result: nil)
            } else {
                ForEach(partners) { DayRow(title: "Partner: \($0.displayName ?? "?")", result: $0) }
            }
        }
    }

    private var historySection: some View {
        Section("Ultimi giorni su CloudKit (entrambi)") {
            if model.cloudResults.isEmpty {
                Text("nessun record").foregroundStyle(.secondary)
            }
            ForEach(model.cloudResults) { result in
                DayRow(title: "\(result.date) - \(result.userId == model.userId ? "io" : (result.displayName ?? "partner"))",
                       result: result)
            }
        }
    }

    private var experimentsSection: some View {
        Section {
            Toggle("Estensione: prova HTTPS", isOn: $model.probeNetwork)
            Toggle("Estensione: scrivi su CloudKit", isOn: $model.probeCloudKit)
        } header: {
            Text("Esperimenti domanda 2")
        } footer: {
            Text("Eseguiti dentro eventDidReachThreshold. Esito nel log (probe.*). Uno '.start' senza esito = estensione terminata prima della fine.")
        }
    }

    private var logSection: some View {
        Section {
            Button("Aggiorna") { model.refresh() }
            Button("Svuota log", role: .destructive) { model.clearLog() }
            ForEach(Array(model.log.suffix(150).reversed())) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.at.formatted(date: .abbreviated, time: .standard)) [\(entry.source)] \(entry.kind)")
                        .font(.caption.monospaced())
                        .foregroundStyle(entry.kind == LogKind.thresholdReached ? Color.orange : Color.primary)
                    if !entry.detail.isEmpty {
                        Text(entry.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Log eventi (\(model.log.count))")
        }
    }
}

private struct DayRow: View {
    let title: String
    let result: DayResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                if let result {
                    Text(result.exceeded ? "SUPERATA" : "non superata")
                        .foregroundStyle(result.exceeded ? Color.red : Color.green)
                        .bold()
                } else {
                    Text("n/d").foregroundStyle(.secondary)
                }
            }
            if let result {
                Text(detail(result)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ r: DayResult) -> String {
        var parts = ["soglia \(r.threshold) min"]
        if let at = r.exceededAt { parts.append("superata alle \(AppModel.timeString(at))") }
        if let updated = r.updatedAt { parts.append("agg. \(updated.formatted(date: .abbreviated, time: .standard))") }
        return parts.joined(separator: " - ")
    }
}
