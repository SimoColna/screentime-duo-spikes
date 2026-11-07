# screentime-duo-spikes

Spike tecnico per un'app iPhone di coppia: ognuno sceglie le proprie app social e una soglia giornaliera; ogni giorno l'app deve sapere, per **entrambi**, se la soglia e' stata superata.

Il codice e' volutamente minimale (nessuna grafica, nessun gioco): autorizzazione Screen Time, picker app, soglia configurabile, monitor `DeviceActivity`, log eventi, sync CloudKit, invito del partner, schermata debug con lo stato di entrambi.

Risposte alle domande, fonti, rischi e raccomandazione go/no-go: **[SPIKE.md](SPIKE.md)**.

## Struttura

```
project.yml                 # spec XcodeGen (2 target + schema)
Config/Base.xcconfig        # Team, bundle ID prefix, App Group, container CloudKit  <- da modificare
App/                        # app SwiftUI "DuoSpike"
  DuoSpikeApp.swift           scenePhase -> sync in foreground, schedula BGAppRefresh
  AppDelegate.swift           BGTaskScheduler, push silenziose CloudKit, scene delegate
  SceneDelegate.swift         accettazione dell'invito CKShare
  AppModel.swift              stato + azioni (auth, monitor, coppia, sync)
  CloudSync.swift             CloudKit: zona condivisa, CKShare, upsert/fetch DayResult, subscription
  ContentView.swift           unica schermata (Form) con tutte le sezioni + debug
Monitor/                    # estensione DeviceActivityMonitor "DuoMonitor"
  DeviceActivityMonitorExtension.swift   scrive gli eventi nel log dell'App Group
  Probes.swift                esperimenti: HTTPS e scrittura CloudKit dall'estensione
Shared/                     # compilato in entrambi i target
  SharedConfig.swift          ID, nomi attivita'/evento, DayKey
  SharedSettings.swift        UserDefaults dell'App Group
  EventLog.swift              log JSONL append-only nell'App Group
  DayResult.swift             record {date, userId, threshold, exceeded} <-> CKRecord
.github/workflows/build.yml # build senza firma su runner macOS
```

Gli `Info.plist` e i `.entitlements` vengono **generati da XcodeGen** a partire da `project.yml` (sono in `.gitignore`).

### Flusso dati

```
iPhone A                                              iPhone B
FamilyActivityPicker + soglia                         (uguale)
   │ startMonitoring(00:00-23:59, repeats, evento soglia)
   ▼
DuoMonitor (estensione) ── eventDidReachThreshold ──► events.jsonl (App Group)
                                                         │
App DuoSpike (foreground / BGAppRefresh / push) ◄────────┘
   │ DayResult(date, userId, threshold, exceeded)
   ▼
CloudKit: zona "DuoZone" nel DB privato del proprietario, condivisa con CKShare(recordZoneID:)
   ▲   owner scrive via privateCloudDatabase, partner via sharedCloudDatabase
   └── CKDatabaseSubscription -> push silenziosa -> l'app dell'altro scarica e mostra lo stato
```

## Requisiti

| Cosa | Note |
|---|---|
| Mac con Xcode 16+ | La CI compila con Xcode 26.3. |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | `brew install xcodegen` |
| **Apple Developer Program a pagamento** (99 USD/anno) | Un Apple ID gratuito (Personal Team) **non basta**: Family Controls (development), CloudKit e Push non sono disponibili senza abbonamento. Vedi SPIKE.md §4. **Basta un solo account**: entrambi gli iPhone si registrano nello stesso team. |
| 2 iPhone, iOS 16.0+ | Consigliato 17.4+ (serve per `includesPastActivity`). Il simulatore non serve per questo spike: le soglie non scattano in modo affidabile. |
| 2 Apple ID **diversi** connessi a iCloud | Un Apple ID per telefono, iCloud Drive attivo. L'Apple ID del telefono non c'entra con l'account sviluppatore. |
| Tempo di utilizzo attivo su entrambi | Impostazioni > Tempo di utilizzo. |

## 1. Generare il progetto

1. Modifica `Config/Base.xcconfig`:
   - `BUNDLE_ID_PREFIX`: un ID univoco tuo, per esempio `com.tuonome.duospike`. Da qui derivano:
     - app `com.tuonome.duospike`, estensione `com.tuonome.duospike.monitor`
     - App Group `group.com.tuonome.duospike`
     - container CloudKit `iCloud.com.tuonome.duospike`
   - `DEVELOPMENT_TEAM`: il tuo Team ID (opzionale, puoi sceglierlo in Xcode).
2. Genera e apri il progetto:
   ```bash
   brew install xcodegen
   xcodegen generate
   open DuoSpike.xcodeproj
   ```
   Rigenera dopo ogni modifica a `project.yml`. Le modifiche a `Base.xcconfig` non richiedono di rigenerare.

## 2. Firma

Con firma automatica (default):

1. In Xcode seleziona il target **DuoSpike**, poi **Signing & Capabilities**, e scegli il Team. Ripeti per **DuoMonitor**.
2. Xcode registra gli App ID e aggiunge le capability presenti negli entitlements:
   - Family Controls (development), su **entrambi** i target
   - App Groups, su entrambi
   - iCloud > CloudKit, su entrambi (sull'estensione serve solo per l'esperimento della domanda 2)
   - Push Notifications, solo app (per le push silenziose di CloudKit)
   - Background Modes `fetch` e `remote-notification`, solo app
3. Se Xcode segnala che l'App Group o il container CloudKit non esistono, crea gli identificatori dalla sezione della capability (pulsante `+` o refresh), oppure su developer.apple.com > Certificates, IDs & Profiles > Identifiers (App Groups / iCloud Containers). Usa esattamente gli ID derivati sopra.
4. Se la capability **Family Controls** non compare o la firma fallisce con "Personal development teams ... do not support the Family Controls capability", stai usando un account gratuito.

## 3. Installare su due iPhone

1. Su ciascun iPhone attiva Impostazioni > Privacy e sicurezza > **Modalita' sviluppatore** (iOS 16+) e riavvia.
2. Collega il telefono A, selezionalo come destinazione ed esegui (⌘R) con lo schema **DuoSpike**. Xcode registra il device nel team.
3. Ripeti con il telefono B (stesso team sviluppatore, ma con un **altro** Apple ID iCloud sul telefono).
4. Il primo avvio in ambiente Development crea in automatico il record type `DayResult` (lo vedi su [CloudKit Console](https://icloud.developer.apple.com/)).

Per i log dell'estensione: `print` non compare nel debugger perche' l'estensione gira in un altro processo. Usa la sezione **Log eventi** dell'app (file `events.jsonl` nell'App Group).

## 4. Piano di test

Usa la tabella in fondo per annotare i risultati. Annota sempre la versione di iOS: i bug noti dipendono dalla versione (SPIKE.md §1).

### Preparazione (entrambi i telefoni)

| # | Passo | Atteso |
|---|---|---|
| P1 | Sezione 1: **Richiedi autorizzazione** | Face ID/codice; stato `approved`. Log `auth ok`. |
| P2 | Sezione 2: **Scegli app**, seleziona 1 app social (es. Instagram) | "1 app, 0 categorie, ...". |
| P3 | Sezione 3: soglia **1 min**, `includesPastActivity` **OFF** per il primo test | Con ON, l'uso precedente di oggi conta e l'evento puo' scattare subito. |
| P4 | Sezione 4: **Avvia monitoraggio** | Attivita' `duo.daily`, soglia attiva 1 min, log `monitor.start`. |
| P5 | Imposta un **Nome visualizzato** diverso su ciascun telefono | |

### Coppia e invito

| # | Passo | Atteso |
|---|---|---|
| C1 | Telefono A: **Crea coppia e invita il partner** | Si apre `UICloudSharingController`. Invia tramite Messaggi all'Apple ID di B. Ruolo A = `owner`. |
| C2 | Telefono B: tocca il link | Si apre DuoSpike, log `couple.participant`, ruolo B = `participant`. |
| C2b | Se C2 non apre l'app o il ruolo resta `none`: B tocca **Ho accettato un invito: cerca la zona condivisa** | Ruolo `participant`. |
| C2c | Fallback: su A tocca **copia link pubblico (read/write)** e invialo a B | Come C2. Va bene solo per lo spike: chiunque abbia il link puo' entrare. |
| C3 | Entrambi: **Sincronizza ora** | "Ultimi giorni su CloudKit": 2 record di oggi, uno per utente, `non superata`. Su A, "Partecipanti" mostra B `accepted`. |

### Soglia e sync (test principale)

| # | Passo | Atteso / da misurare |
|---|---|---|
| T1 | Telefono A: usa l'app social con schermo acceso per **2-3 minuti** | |
| T2 | Apri DuoSpike su A, Log eventi | `[ext] eventDidReachThreshold`. Annota l'orario rispetto all'inizio dell'uso: **latenza evento**. |
| T3 | Confronta con Impostazioni > Tempo di utilizzo su A | I minuti devono essere ≥ soglia. Se l'evento scatta con 0 minuti, e' un **falso positivo**. |
| T4 | L'apertura di A ha gia' sincronizzato (log `sync.ok (foreground)`) | Su B, entro pochi secondi (push silenziosa) o dopo un pull-to-refresh: **Partner: A → SUPERATA**. Annota la **latenza di sync**. |
| T5 | Ripeti con A che **non** apre l'app: lascia DuoSpike in background, senza chiuderla | Annota se e quando B vede SUPERATA (`bg.refresh` nel log di A). Ripeti con DuoSpike chiusa dal multitasking (atteso: niente BG refresh). |
| T6 | Ripeti T1-T4 a ruoli invertiti (B supera, A osserva) | Verifica che anche il participant scriva nella zona condivisa. |

### Domanda 2: rete e CloudKit dall'estensione

| # | Passo | Atteso / da misurare |
|---|---|---|
| E1 | Su A attiva **Estensione: prova HTTPS** ed **Estensione: scrivi su CloudKit** | |
| E2 | Fai scattare una soglia non ancora raggiunta: soglia 2 min, riavvia monitor, usa l'app social | |
| E3 | Log di A: `probe.network` / `probe.cloudkit` | Esito (`HTTP 200`, `ok`, `error ...`, `timeout`) e durata. Un `.start` **senza** esito significa che l'estensione e' stata terminata. |
| E4 | Su B, **senza aprire DuoSpike su A**: pull-to-refresh | Se compare un DayResult di A con nome "... (ext)", la scrittura CloudKit diretta dall'estensione funziona. Ripeti 5-10 volte e annota il tasso di successo. |

### Mezzanotte, spegnimento, riavvio

| # | Passo | Atteso / da misurare |
|---|---|---|
| M1 | Lascia i telefoni accesi la notte. Al mattino controlla il log | `intervalDidEnd` + `intervalDidStart`. Annota **l'orario reale**: da WWDC21 ci si aspetta il primo utilizzo dopo mezzanotte, non le 00:00 esatte. Il nuovo giorno e' `non superata`. |
| M2 | Telefono spento alle 23:50, riacceso alle 00:10 | Arrivano `intervalDidEnd`/`intervalDidStart` dopo lo sblocco? Il giorno precedente resta corretto? |
| M3 | Riavvio a meta' giornata, **prima** di raggiungere la soglia. Dopo lo sblocco usa l'app social | Compare `ext.init`? `eventDidReachThreshold` scatta comunque? `duo.daily` e' ancora tra le attivita' registrate? |
| M4 | Riavvio **dopo** aver superato la soglia | Nessun secondo evento (oppure un duplicato: annotalo). |
| M5 | Cambio fuso orario (opzionale) | Annota cosa succede al `DayKey`. |

### Affidabilita' (soak test)

| # | Passo | Atteso / da misurare |
|---|---|---|
| S1 | 7 giorni con soglie realistiche (15-60 min), `includesPastActivity` ON | Ogni sera confronta il log con Tempo di utilizzo: veri positivi, falsi positivi, eventi mancati. |
| S2 | iOS 26.x: soglia 15 min, telefono in carica di notte senza usarlo | Bug noto (Apple "known issue"): evento allo sblocco o in carica con 0 minuti. Annota se succede. |
| S3 | Eventi duplicati | Piu' `eventDidReachThreshold` nello stesso giorno: contali. |

### Scheda risultati

| Test | iOS A | iOS B | Esito | Latenza | Note |
|---|---|---|---|---|---|
| T2 | | | | | |
| T4 | | | | | |
| E3 | | | | | |
| E4 | | | | | |
| M1 | | | | | |
| M2 | | | | | |
| M3 | | | | | |
| S1 (7 gg) | | | | | |

## CI

`.github/workflows/build.yml` gira su `macos-15`, installa XcodeGen, genera il progetto e compila app ed estensione per `generic/platform=iOS` con `CODE_SIGNING_ALLOWED=NO`. Poi verifica che `DuoMonitor.appex` sia incorporata nell'app con il giusto `NSExtensionPointIdentifier`. Gira a ogni push e PR, e anche a mano (`workflow_dispatch`).

## Verso TestFlight (non necessario per lo spike)

1. Chiedi a Apple la **Family Controls (Distribution)**: [modulo](https://developer.apple.com/contact/request/family-controls-distribution), con login. Conta di dover fare **una richiesta per ogni bundle ID**: app **e** `.monitor`. Lo riportano piu' sviluppatori; Apple non lo ha confermato (SPIKE.md §4).
2. Dopo l'approvazione, abilita la distribuzione per ciascun identifier nel portale e rigenera i profili App Store.
3. CloudKit Console: **Deploy Schema Changes** in Production. TestFlight e App Store usano l'ambiente Production.
4. `aps-environment` viene impostato su production dal profilo di distribuzione all'export.
