# screentime-duo-spikes

Spike tecnico per un'app di coppia (iOS + Android): ognuno sceglie le proprie app social e una soglia giornaliera; ogni giorno l'app deve sapere, per **entrambi**, se la soglia e' stata superata.

Questo repository copre **solo la parte iOS Screen Time**: autorizzazione, picker app, soglia configurabile, monitor `DeviceActivity`, log eventi, diagnosi dei falsi positivi e schermata debug con lo stato di entrambi. Il backend non e' ancora scelto: il sync sta dietro il protocollo `SyncService`, che nello spike e' implementato da un **fake locale** con un partner simulato.

Risposte alle domande, fonti, rischi e raccomandazione go/no-go: **[SPIKE.md](SPIKE.md)**.

## Struttura

```
project.yml                 # spec XcodeGen (2 target + schema)
Config/Base.xcconfig        # Team, bundle ID prefix, App Group  <- da modificare
App/                        # app SwiftUI "DuoSpike"
  DuoSpikeApp.swift           scenePhase -> sync in foreground, schedula BGAppRefresh
  AppDelegate.swift           BGTaskScheduler (sync in background)
  AppModel.swift              stato + azioni (auth, monitor, coppia, sync)
  ThresholdDiagnostics.swift  diagnosi dei falsi positivi con gli eventi "gradino"
  ContentView.swift           unica schermata (Form) con tutte le sezioni + debug
  Sync/SyncService.swift      interfaccia verso il backend (da scegliere)
  Sync/LocalFakeSyncService.swift  implementazione finta, locale, con partner simulato
Monitor/                    # estensione DeviceActivityMonitor "DuoMonitor"
  DeviceActivityMonitorExtension.swift   scrive gli eventi nel log dell'App Group
  Probes.swift                esperimenti: HTTPS e notifica locale dall'estensione
Shared/                     # compilato in entrambi i target
  SharedConfig.swift          ID, nomi attivita'/eventi, DayKey
  SharedSettings.swift        UserDefaults dell'App Group
  EventLog.swift              log JSONL append-only nell'App Group
  DayResult.swift             record {date, userId, threshold, exceeded} (Codable)
.github/workflows/build.yml # build senza firma su runner macOS
```

Gli `Info.plist` e i `.entitlements` vengono **generati da XcodeGen** a partire da `project.yml` (sono in `.gitignore`).

### Flusso dati

```
FamilyActivityPicker + soglia N
   │ startMonitoring(00:00-23:59, repeats,
   │   eventi: soglia N + gradini 25/50/75% di N)
   ▼
DuoMonitor (estensione) ── eventDidReachThreshold ──► events.jsonl (App Group)
   │ (opz.) probe HTTPS / notifica locale                 │
   ▼                                                      ▼
App DuoSpike (foreground / BGAppRefresh / pull-to-refresh / tap sulla notifica)
   │ ricalcola DayResult dal log + diagnosi dei falsi positivi
   ▼
SyncService  ──►  LocalFakeSyncService (spike)   |   backend reale (dopo; condiviso con Android)
```

## Requisiti

| Cosa | Note |
|---|---|
| Mac con Xcode 16+ | La CI compila con Xcode 26.3. |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | `brew install xcodegen` |
| **Apple Developer Program a pagamento** (99 USD/anno) | Un Apple ID gratuito (Personal Team) **non basta**: Family Controls (development) non e' disponibile senza abbonamento. Vedi SPIKE.md §4. Basta un solo account per piu' iPhone. |
| 1 o 2 iPhone, iOS 16.0+ | Consigliato 17.4+ (serve per `includesPastActivity`). Con due iPhone, meglio uno su **iOS 26.x** e uno su **iOS 27**, per coprire il bug noto. Il simulatore non serve: le soglie non scattano in modo affidabile. |
| Tempo di utilizzo attivo | Impostazioni > Tempo di utilizzo. |

## 1. Generare il progetto

1. Modifica `Config/Base.xcconfig`:
   - `BUNDLE_ID_PREFIX`: un ID univoco tuo, per esempio `com.tuonome.duospike`. Da qui derivano:
     - app `com.tuonome.duospike`, estensione `com.tuonome.duospike.monitor`
     - App Group `group.com.tuonome.duospike`
   - `DEVELOPMENT_TEAM`: il tuo Team ID (opzionale, puoi sceglierlo in Xcode).
2. Genera e apri il progetto:
   ```bash
   brew install xcodegen
   xcodegen generate
   open DuoSpike.xcodeproj
   ```
   Rigenera dopo ogni modifica a `project.yml`.

## 2. Firma

Con firma automatica (default):

1. In Xcode seleziona il target **DuoSpike**, poi **Signing & Capabilities**, e scegli il Team. Ripeti per **DuoMonitor**.
2. Xcode registra gli App ID e aggiunge le capability presenti negli entitlements:
   - Family Controls (development), su **entrambi** i target
   - App Groups, su entrambi
   - Background Modes `fetch`, solo app
3. Se Xcode segnala che l'App Group non esiste, crealo dalla sezione della capability (pulsante `+`) oppure su developer.apple.com > Identifiers > App Groups, con esattamente l'ID derivato sopra.
4. Se la capability **Family Controls** non compare o la firma fallisce con "Personal development teams ... do not support the Family Controls capability", stai usando un account gratuito.

## 3. Installare su iPhone

1. Su ciascun iPhone attiva Impostazioni > Privacy e sicurezza > **Modalita' sviluppatore** (iOS 16+) e riavvia.
2. Collega il telefono, selezionalo come destinazione ed esegui (⌘R) con lo schema **DuoSpike**. Xcode registra il device nel team.
3. Per il soak test conviene anche un'installazione in configurazione **Release**: Product > Scheme > Edit Scheme > Run > Build Configuration. Alcuni sviluppatori riportano comportamenti diversi tra debug e release (thread 749263).

Per i log dell'estensione: `print` non compare nel debugger perche' l'estensione gira in un altro processo. Usa la sezione **Log eventi** dell'app (file `events.jsonl` nell'App Group). Il pulsante **Esporta log (JSONL)** lo condivide (AirDrop, File, Mail) per analizzarlo dopo.

## 4. Piano di test

Usa la scheda in fondo per annotare i risultati. Annota sempre la versione di iOS: i bug noti dipendono dalla versione (SPIKE.md §1). Con due iPhone esegui gli stessi test su entrambi, uno per versione di iOS.

### Preparazione

| # | Passo | Atteso |
|---|---|---|
| P1 | Sezione 1: **Richiedi autorizzazione** | Face ID/codice; stato `approved`. Log `auth ok`. |
| P2 | Sezione 2: **Scegli app**, seleziona 1 app social (es. Instagram) | "1 app, 0 categorie, ...". |
| P3 | Sezione 3: soglia **4 min**, `includesPastActivity` **OFF** per il primo test | 4 min e' il minimo per avere i gradini 1/2/3 min. Con ON, l'uso precedente di oggi conta e gli eventi possono scattare subito. |
| P4 | Sezione 4: **Avvia monitoraggio** | Attivita' `duo.daily`, "Soglia attiva 4 min (gradini 25%/50%/75%)", log `monitor.start`. |
| P5 | Sezione 5: **Crea invito per il partner** | Backend "Fake locale", codice `DUO-xxxx`, partner "Partner simulato". |

### Domanda 1: soglia ed eventi

| # | Passo | Atteso / da misurare |
|---|---|---|
| T1 | Usa l'app social con schermo acceso per **5-6 minuti** di fila | |
| T2 | Apri DuoSpike, Log eventi | In ordine: `eventDidReachThreshold.ladder` 25%, 50%, 75%, poi `[ext] eventDidReachThreshold`. Annota l'orario rispetto all'inizio dell'uso: **latenza evento**. |
| T3 | Sezione "Diagnosi falsi positivi" | Oggi = **plausibile**. |
| T4 | Confronta con Impostazioni > Tempo di utilizzo | I minuti devono essere ≥ soglia. Se l'evento scatta con 0 minuti, e' un **falso positivo**: annota se la diagnosi l'ha segnato SOSPETTO. |
| T5 | Debug "oggi": Io (log locale) = SUPERATA; dopo il sync anche "Io (copia sul backend)" = SUPERATA | Il percorso estensione → log → app → SyncService funziona. |
| T6 | Domani: soglia 1 min, `includesPastActivity` ON, avvia il monitor dopo aver gia' usato l'app social | Evento quasi immediato (uso passato incluso); diagnosi "non valutabile" perche' e' dentro 2 min dal `monitor.start`. |

### Domanda 2: rete e notifiche dall'estensione

| # | Passo | Atteso / da misurare |
|---|---|---|
| E1 | Attiva **Estensione: richiesta HTTPS** (URL vuoto = GET alla pagina di test Apple) | |
| E2 | Attiva **Estensione: notifica locale** e concedi il permesso | Log `notifications.auth granted`. |
| E3 | Fai scattare una soglia non ancora raggiunta oggi (soglia 5 min, riavvia monitor, usa l'app social) | Log: `probe.network` con `HTTP 200` e durata, `probe.notification ok`, e la notifica "Soglia superata" sullo schermo. Un `.start` **senza** esito significa che l'estensione e' stata terminata. |
| E4 | Opzionale: inserisci un URL POST di test tuo (un endpoint che registra le richieste ricevute) e ripeti E3 | Il JSON del `DayResult` arriva al server? Ripeti 5-10 volte e annota il tasso di successo. |
| E5 | Tocca la notifica | DuoSpike si apre e sincronizza (`sync.ok (foreground)`). |
| E6 | Background: lascia DuoSpike in background senza chiuderla e controlla piu' tardi `bg.refresh` nel log | Annota dopo quanto tempo arriva, se arriva. Ripeti con l'app chiusa dal multitasking (atteso: niente BG refresh). |

### Sync tramite `SyncService` (fake)

| # | Passo | Atteso |
|---|---|---|
| S1 | **Partner simulato: SUPERATA oggi** | Debug "oggi": Partner = SUPERATA. |
| S2 | **Backend offline** ON, poi **Sincronizza ora** | Errore "Backend non raggiungibile (simulato)" e `sync.error` nel log; lo stato locale resta corretto. |
| S3 | Backend offline OFF, poi pull-to-refresh | Il sync recupera da solo, senza duplicati (upsert idempotente). |

### Mezzanotte, spegnimento, riavvio

| # | Passo | Atteso / da misurare |
|---|---|---|
| M1 | Lascia il telefono acceso la notte. Al mattino controlla il log | `intervalDidEnd` + `intervalDidStart`. Annota **l'orario reale**: da WWDC21 ci si aspetta il primo utilizzo dopo mezzanotte, non le 00:00 esatte. Il nuovo giorno e' `non superata`. |
| M2 | Telefono spento alle 23:50, riacceso alle 00:10 | Arrivano `intervalDidEnd`/`intervalDidStart` dopo lo sblocco? Il giorno precedente resta corretto? |
| M3 | Riavvio a meta' giornata, **prima** di raggiungere la soglia. Dopo lo sblocco usa l'app social | Compare `ext.init`? Gradini e soglia arrivano comunque? `duo.daily` e' ancora tra le attivita' registrate? |
| M4 | Riavvio **dopo** aver superato la soglia | Nessun secondo evento (oppure un duplicato: annotalo; la diagnosi conta i duplicati). |
| M5 | Cambio fuso orario (opzionale) | Annota cosa succede al `DayKey`. |

### Affidabilita' (soak test, 7 giorni)

| # | Passo | Atteso / da misurare |
|---|---|---|
| K1 | Soglia realistica (15-60 min), `includesPastActivity` ON, build Release | Ogni sera: diagnosi del giorno + confronto con Tempo di utilizzo. Classifica: vero positivo, falso positivo (rilevato o no dalla diagnosi), evento mancato. |
| K2 | Su iOS 26.x: telefono in carica di notte senza usarlo | Bug noto: evento allo sblocco o in carica con 0 minuti. Annota se succede e cosa dice la diagnosi. |
| K3 | A fine settimana: **Esporta log** da ogni telefono | Allega i JSONL ai risultati. |

### Scheda risultati

| Test | iOS | Esito | Latenza | Diagnosi | Note |
|---|---|---|---|---|---|
| T2 | | | | | |
| T4 | | | | | |
| E3 | | | | | |
| E4 | | | | | |
| E6 | | | | | |
| M1 | | | | | |
| M2 | | | | | |
| M3 | | | | | |
| K1 (7 gg) | | | | | |
| K2 | | | | | |

## Sostituire il backend finto

Implementa `SyncService` (`App/Sync/SyncService.swift`) per il backend scelto e cambia una riga in `AppModel`:

```swift
static let shared = AppModel(sync: LocalFakeSyncService())   // -> MyBackendSyncService()
```

Il contratto atteso (upsert idempotente su (userId, date), scrittura solo dei propri record, lettura della coppia, push al partner dal server) e' descritto nel protocollo e in SPIKE.md § "Sync".

## CI

`.github/workflows/build.yml` gira su `macos-15`, installa XcodeGen, genera il progetto e compila app ed estensione per `generic/platform=iOS` con `CODE_SIGNING_ALLOWED=NO`. Poi verifica che `DuoMonitor.appex` sia incorporata nell'app con il giusto `NSExtensionPointIdentifier`. Gira a ogni push e PR, e anche a mano (`workflow_dispatch`).

## Verso TestFlight (non necessario per lo spike)

1. Chiedi a Apple la **Family Controls (Distribution)**: [modulo](https://developer.apple.com/contact/request/family-controls-distribution), con login. Conta di dover fare **una richiesta per ogni bundle ID**: app **e** `.monitor`. Lo riportano piu' sviluppatori; Apple non lo ha confermato (SPIKE.md §4).
2. Dopo l'approvazione, abilita la distribuzione per ciascun identifier nel portale e rigenera i profili App Store.
