import FamilyControls
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPicker = false
    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            Form {
                authorizationSection
                selectionSection
                thresholdSection
                monitorSection
                pairSection
                if model.fakeSync != nil { fakeSection }
                todaySection
                diagnosisSection
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
            Text("Prodotto: 15-60 min. 1-14 solo per i test; da 4 min in su vengono registrati anche i gradini 25/50/75% per la diagnosi. includesPastActivity ha effetto da iOS 17.4. Riavvia il monitor dopo ogni modifica.")
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

    // MARK: 5: Coppia (SyncService)

    private var pairSection: some View {
        Section {
            LabeledContent("Backend", value: model.sync.backendName)
            LabeledContent("Mio userId", value: model.userId ?? "-")
            TextField("Nome visualizzato", text: $model.displayName)
            if let pairing = model.pairing {
                LabeledContent("Coppia", value: String(pairing.pairId.prefix(8)))
                LabeledContent("Partner", value: model.partner?.displayName ?? "-")
                if let invite = model.lastInvite {
                    LabeledContent("Codice invito", value: invite.code)
                }
                Button("Esci dalla coppia", role: .destructive) { Task { await model.leavePair() } }
            } else {
                Button("Crea invito per il partner") { Task { await model.createInvite() } }
                HStack {
                    TextField("Codice ricevuto", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                    Button("Entra") { Task { await model.acceptInvite(code: inviteCode) } }
                        .disabled(inviteCode.isEmpty)
                }
            }
            Button("Sincronizza ora") { Task { await model.syncNow(reason: "manual") } }
            LabeledContent("Ultimo sync") { Text(model.lastSyncDescription).font(.caption) }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(Color.red)
            }
        } header: {
            Text("5. Coppia (SyncService)")
        }
    }

    private var fakeSection: some View {
        Section {
            Button("Partner simulato: SUPERATA oggi") { Task { await model.simulatePartnerToday(exceeded: true) } }
            Button("Partner simulato: non superata oggi") { Task { await model.simulatePartnerToday(exceeded: false) } }
            Toggle("Backend offline", isOn: $model.fakeOffline)
            Button("Azzera backend finto", role: .destructive) { model.wipeFakeBackend() }
        } header: {
            Text("Simulazione backend")
        } footer: {
            Text("Il backend e' finto e locale: il partner non e' un altro telefono. Con 'offline' il sync fallisce e al giro successivo deve recuperare da solo (idempotenza).")
        }
    }

    // MARK: 6: Debug

    private var todaySection: some View {
        let today = DayKey.string(from: Date())
        return Section("6. Debug: oggi \(today)") {
            DayRow(title: "Io (log locale)", result: model.localResults.first { $0.date == today })
            DayRow(title: "Io (copia sul backend)", result: model.myRemoteResults.first { $0.date == today })
            DayRow(title: "Partner: \(model.partner?.displayName ?? "-")",
                   result: model.partnerResults.first { $0.date == today })
        }
    }

    private var diagnosisSection: some View {
        Section {
            ForEach(model.diagnoses) { day in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(day.day)
                        Spacer()
                        Text(day.verdict.label)
                            .bold()
                            .foregroundStyle(color(for: day.verdict))
                    }
                    Text(diagnosisDetail(day)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Diagnosi falsi positivi (domanda 1)")
        } footer: {
            Text("SOSPETTO = soglia arrivata senza i gradini precedenti, o prima del tempo minimo di uso. Confronta sempre con Impostazioni > Tempo di utilizzo.")
        }
    }

    private var historySection: some View {
        Section("Ultimi giorni sul backend (entrambi)") {
            if model.pairResults.isEmpty {
                Text("nessun record").foregroundStyle(.secondary)
            }
            ForEach(model.pairResults) { result in
                DayRow(title: "\(result.date) - \(result.userId == model.userId ? "io" : (result.displayName ?? "partner"))",
                       result: result)
            }
        }
    }

    private var experimentsSection: some View {
        Section {
            Toggle("Estensione: richiesta HTTPS", isOn: $model.probeNetwork)
            TextField("URL POST (vuoto = GET test Apple)", text: $model.probeURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            Toggle("Estensione: notifica locale", isOn: $model.probeNotification)
        } header: {
            Text("Esperimenti domanda 2")
        } footer: {
            Text("Eseguiti dentro eventDidReachThreshold (solo per la soglia, non per i gradini). Esito nel log (probe.*). Un '.start' senza esito = estensione terminata prima della fine.")
        }
    }

    private var logSection: some View {
        Section {
            Button("Aggiorna") { model.refresh() }
            if let url = EventLog.fileURL {
                ShareLink("Esporta log (JSONL)", item: url)
            }
            Button("Svuota log", role: .destructive) { model.clearLog() }
            ForEach(Array(model.log.suffix(200).reversed())) { entry in
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

    // MARK: Helpers

    private func color(for verdict: ThresholdDiagnostics.Verdict) -> Color {
        switch verdict {
        case .plausible: return .green
        case .suspicious: return .red
        case .notAssessable: return .orange
        case .noEvent: return .secondary
        }
    }

    private func diagnosisDetail(_ day: ThresholdDiagnostics.Day) -> String {
        var parts: [String] = []
        if let at = day.thresholdAt, let minutes = day.thresholdMinutes {
            parts.append("soglia \(minutes) min alle \(AppModel.timeString(at))")
        }
        if day.thresholdCount > 1 { parts.append("\(day.thresholdCount) eventi soglia (duplicati)") }
        let ladder = day.ladder.keys.sorted().map { "\($0)%@\(AppModel.timeString(day.ladder[$0]!))" }
        if !ladder.isEmpty { parts.append("gradini " + ladder.joined(separator: " ")) }
        if let reason = day.verdict.reason { parts.append(reason) }
        return parts.isEmpty ? "-" : parts.joined(separator: " - ")
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
