# SPIKE: API Screen Time per una soglia giornaliera sui social (app di coppia)

Ricerca aggiornata al 7 novembre 2026. **Ambito**: domande 1, 2 e 4, cioe' le API Screen Time su iOS. L'app sara' cross-platform (iOS + Android): il backend e' rimandato e il sync sta dietro l'interfaccia `SyncService`, che nello spike e' implementata da un fake locale (§ "Sync").

Il codice compila in CI (Xcode 26.3, deployment target iOS 16.0) ma **non e' ancora stato eseguito su un device**. Le conclusioni "da verificare" vanno chiuse con il piano di test del [README](README.md#4-piano-di-test).

Legenda:
- ✅ **Verificato**: documentazione Apple o risposta di un ingegnere Apple (badge DTS Engineer / Frameworks Engineer) sui forum.
- 🟡 **Riportato**: piu' sviluppatori sui forum Apple o fonti terze, senza conferma Apple.
- ❓ **Ipotesi**: mio ragionamento o comportamento atteso, non documentato. Da verificare sul device.

---

## TL;DR

| Domanda | Risposta breve |
|---|---|
| 1. `eventDidReachThreshold` e' affidabile? | **Funziona, ma non e' affidabile al 100%.** Apple ha confermato un bug di **falsi positivi** iniziato con iOS 26 ("known issue ... being investigated"). Ad agosto 2026 gli sviluppatori lo segnalano ancora su 26.5.2/26.6; su iOS 27 non ci sono dati. In passato Apple ha riconosciuto un over-counting su 17.6/18.x senza workaround. A mezzanotte i callback arrivano **al primo utilizzo dopo** il confine. Sul riavvio non c'e' documentazione: va testato. Lo spike include una **diagnosi automatica dei falsi positivi** (eventi "gradino" al 25/50/75%). |
| 2. Rete dall'estensione? | **Non in modo affidabile.** Apple: il ciclo di vita finisce quando il metodo sincrono ritorna. Workaround Apple: bloccare con un timeout di ~3 s. Limite memoria ~6 MB (da crash log). Apple conferma invece che **le notifiche locali dall'estensione funzionano**. Strategia: **estensione → App Group → app → `SyncService`**, piu' una notifica locale che invita ad aprire l'app. |
| 4. Entitlement / account | Senza CloudKit bastano **Family Controls + App Groups**, ma serve comunque l'**Apple Developer Program a pagamento**: Family Controls (development) non e' disponibile con l'Apple ID gratuito (verificato sulla tabella Apple). Per TestFlight/App Store serve una richiesta "Family Controls (Distribution)", in pratica una per ogni bundle ID (app ed estensione). |
| iOS minimo | **iOS 16.0** (`requestAuthorization(for: .individual)`). **Consigliato 17.4** per controllare `includesPastActivity`. |
| **Raccomandazione** | **GO condizionato.** Il blocco iOS e' fattibile e il sync si disaccoppia bene dal backend. Il rischio principale e' l'affidabilita' delle soglie su iOS 26.x/27, che Apple non controlla ancora. Il design deve tollerare falsi positivi. Prima del design: soak test di 7 giorni, con la diagnosi dello spike, su iOS 26.x **e** 27. |

---

## 1. Affidabilita' di `eventDidReachThreshold` per una soglia giornaliera

### Come funziona (✅ documentazione Apple)

- `DeviceActivityEvent`: "An application's extension receives a callback once the combination of specified applications, categories, and webDomains have been in use longer than the event's threshold **within the activity's scheduled interval**." Con uno schedule 00:00-23:59 `repeats: true`, il conteggio e' quindi per giorno. ([DeviceActivityEvent init](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/init(applications:categories:webdomains:threshold:includespastactivity:)))
- `includesPastActivity` (**iOS 17.4+**): stabilisce se l'uso precedente all'avvio del monitoraggio conta per la soglia. Esempio Apple: `startMonitoring` alle 13:30 con schedule 13:00-14:00. Per una soglia "giornaliera" vera serve `true`: se l'utente cambia soglia alle 15:00, l'uso dalle 00:00 conta comunque.
- `startMonitoring`: sovrascrive schedule ed eventi di un'attivita' gia' monitorata. Puo' lanciare un errore se ci sono troppe attivita' o se sono troppo ravvicinate. L'estensione "may begin receiving callbacks as soon as the system calls this method if the activity's scheduled interval is ongoing". ([startMonitoring](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)))
- Errori possibili: `excessiveActivities`, `intervalTooLong`, `intervalTooShort`, `invalidDateComponents`, `unauthorized`. ([MonitoringError](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror))
- Le app scelte con `FamilyActivityPicker` arrivano come **token opachi**: l'app non conosce i nomi delle app scelte. I dati di utilizzo restano sul dispositivo ([WWDC21 "Meet the Screen Time API"](https://developer.apple.com/videos/play/wwdc2021/10123/)).
- Per condividere dati tra app ed estensione serve un App Group. `print` dell'estensione non compare nel debugger (altro processo). Lo dice un Frameworks Engineer Apple ([thread 721945](https://developer.apple.com/forums/thread/721945)).
- La lista dei simboli DeviceActivity nella documentazione corrente non mostra novita' per monitor, schedule ed eventi rispetto a iOS 17.4.

### Mezzanotte (✅ in parte, ❓ in parte)

- ✅ WWDC21: "These functions will be called **the first time the device is used after** the start and end of my schedule." `intervalDidEnd` / `intervalDidStart` **non** arrivano alle 00:00 esatte, ma al primo utilizzo successivo. ([WWDC21](https://developer.apple.com/videos/play/wwdc2021/10123/))
- ❓ **Conseguenza per il design**: non si puo' "chiudere" il giorno precedente con un callback a mezzanotte. Nello spike il risultato di un giorno si ricava dal log: `exceeded = true` se c'e' un `eventDidReachThreshold` con quella data. Un giorno passato senza evento si considera `false`. Il giorno corrente resta "non superata finora".
- ❓ Uso a cavallo della mezzanotte (23:50-00:10): dovrebbe dividersi tra i due intervalli. Da verificare (test M1/M2).

### Telefono spento o riavviato (❓ nessuna fonte ufficiale)

- Non ho trovato documentazione Apple ne' risposte Apple sul comportamento dopo un riavvio. In un thread un DTS chiede se il problema avvenga "right after starting monitoring, after a reboot, or after an OS update", segno che il riavvio e' una variabile nota ma non documentata ([thread 809410](https://developer.apple.com/forums/thread/809410)).
- ❓ Ipotesi: le attivita' registrate sono di sistema e persistono (`DeviceActivityCenter.activities`). Dopo il riavvio i callback ripartono al primo utilizzo dopo lo sblocco. Mentre il telefono e' spento non c'e' uso, quindi nulla da contare.
- ❓ Rischio tecnico: prima del primo sblocco dopo il riavvio i file protetti dell'App Group non sono accessibili. In pratica l'utente non usa app prima di sbloccare. Da verificare con il test M3 (cerca `ext.init` nel log).

### Bug noti (✅ confermati da Apple, 🟡 riportati)

| Versione iOS | Problema | Fonte | Stato |
|---|---|---|---|
| 26.0 beta → 26.6 (iOS 27: nessun dato) | Evento **prematuro**, spesso al primo sblocco del mattino o in carica, con 0 minuti in Tempo di utilizzo. Anche l'"App Limit" nativo di iOS risulta colpito. | [thread 809410](https://developer.apple.com/forums/thread/809410) ([pag. 2](https://developer.apple.com/forums/thread/809410?page=2)), [812472](https://developer.apple.com/forums/thread/812472), [811305](https://developer.apple.com/forums/thread/811305) | ✅ DTS Apple (gen 2026): "This is a known issue that is currently being investigated." 🟡 Ad aprile 2026 uno sviluppatore riporta un tentativo di fix in 26.5 beta 1 (dal suo Feedback). A luglio/agosto 2026 altri scrivono "Still having this issue on iOS 26.5.2" e "very likely on iOS 26.6". Nessun fix confermato da Apple. |
| 17.6.1 → 18.x | **Over-counting**: soglia di 300 min scattata a 150 min; eventi multipli in pochi ms. | [thread 763542](https://developer.apple.com/forums/thread/763542) | ✅ DTS Apple (dic 2024): "I don't have any info to share about when, or indeed if, that'll be fixed", "I also can't see any sort of reasonable workaround." |
| 17.4 | `includesPastActivity` ha default `false`, mentre prima il comportamento era come `true`. | [thread 745675](https://developer.apple.com/forums/thread/745675) | 🟡 Nessuna risposta Apple. Nello spike il valore e' **sempre esplicito**. |
| 16.x / 17.x | Callback non chiamato, oppure chiamato piu' volte di seguito. | [thread 741117](https://developer.apple.com/forums/thread/741117), [757722](https://developer.apple.com/forums/thread/757722) | 🟡 Alcuni casi sono errori di configurazione. Lo spike de-duplica (conta il primo evento del giorno) e logga tutti gli eventi. |
| 27 | Su DeviceActivity non trovo release note Apple ne' thread. | [HabitDoom](https://habitdoom.com/blog/wwdc-2026-screen-time-wishlist) (fonte terza) | 🟡 Secondo questa fonte, throttling e callback persi sono invariati nella beta di iOS 27. **Da misurare.** |

### Diagnosi dei falsi positivi (implementata)

Dal codice non si possono leggere i minuti reali di utilizzo: sono accessibili solo in un'estensione `DeviceActivityReport`, che e' sandboxata. Lo riportano gli sviluppatori in [thread 818297](https://developer.apple.com/forums/thread/818297).

Lo spike usa quindi un controllo di plausibilita' (`App/ThresholdDiagnostics.swift`):

- Oltre alla soglia di N minuti si registrano tre eventi "gradino" al 25, 50 e 75% di N, nella stessa attivita'.
- Con uso reale i gradini arrivano **prima** della soglia. Tra il gradino al 25% (m minuti) e la soglia devono passare almeno **N - m minuti di orologio**.
- Se la soglia arriva senza i gradini precedenti, o troppo presto, il giorno e' **SOSPETTO**.
- Dentro 2 minuti da un `startMonitoring` il giorno e' "non valutabile": con `includesPastActivity` tutti gli eventi possono arrivare insieme legittimamente.

❓ Non so ancora come si presenta il bug di iOS 26: tutti gli eventi insieme (rilevabile), oppure solo la soglia (rilevabile)? Lo dira' il soak test. Se la diagnosi intercetta i falsi positivi, puo' diventare una **mitigazione di prodotto**: un evento sospetto non viene comunicato al partner, oppure viene marcato come "da confermare".

### Risposta

Il meccanismo e' quello giusto e, quando funziona, fa esattamente cio' che serve: soglia giornaliera su app scelte dall'utente, senza conoscerne i nomi. Ma **non e' affidabile al 100%** e la parte inaffidabile e' fuori dal nostro controllo: Apple conferma falsi positivi da iOS 26 senza fix confermato e non offre workaround per l'over-counting. Il soak test deve coprire **sia iOS 26.x sia iOS 27**.

---

## 2. Rete dall'estensione DeviceActivityMonitor

### Cosa dice Apple (✅)

- Frameworks Engineer Apple, risposta accettata in [thread 724649](https://developer.apple.com/forums/thread/724649) (feb 2023): "DeviceActivityMonitor extensions are intended to be very lightweight and **their lifecycle ends as soon as the synchronous methods you override return**." Una richiesta di rete asincrona verra' quindi probabilmente interrotta. Suggerisce di aprire un enhancement request per callback asincrone e, come workaround, un `DispatchGroup` con `wait(timeout: 3.0)`.
- Frameworks Engineer Apple, [thread 727017](https://developer.apple.com/forums/thread/727017) (mar 2023): "**Yes, you should be able to post user notifications from a DeviceActivity monitor extension.**" Nello stesso thread Apple chiarisce che `NotificationCenter` funziona solo dentro un processo: non collega estensione e app.
- Non ho trovato documentazione che **vieti** la rete nell'estensione Monitor. Il divieto esplicito riguarda l'estensione Report, secondo i thread degli sviluppatori.

### Cosa riportano gli sviluppatori (🟡)

- Il server riceve "rarely" le POST fatte da `intervalDidEnd`. Con due richieste in sequenza parte solo la prima ([thread 724649](https://developer.apple.com/forums/thread/724649)).
- Limite di memoria **6 MB**: lo mostra un crash log `EXC_RESOURCE ... (limit=6 MB)` del 2023 ([thread 735454](https://developer.apple.com/forums/thread/735454); la risposta accettata non e' di Apple). Uno sviluppatore ha chiesto ad Apple di alzarlo ([823431](https://developer.apple.com/forums/thread/823431)); altri segnalano crash di memoria imprevedibili su iOS 26 ([827783](https://developer.apple.com/forums/thread/827783)).
- Le Darwin notification estensione → app arrivano solo se l'app e' in esecuzione ([thread 749263](https://developer.apple.com/forums/thread/749263)). Quindi non servono a "svegliare" l'app.

### Risposta e scelta implementata

- ❓ Ipotesi: si puo' tentare una richiesta HTTPS bloccando il thread per qualche secondo, ma il successo non e' garantito (ciclo di vita, 6 MB, rete assente in quel momento). **Non e' una base su cui costruire il prodotto.**
- **Strategia principale (implementata)**: l'estensione scrive **solo** una riga nel log JSONL dell'App Group (`events.jsonl`, append, pochi KB). L'app principale ricalcola i `DayResult` dal log e li invia tramite `SyncService`:
  1. all'apertura o al ritorno in foreground (`scenePhase == .active`);
  2. con `BGAppRefreshTask` (✅ richiede la background mode `fetch`, [doc](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask); ❓ iOS decide quando eseguirlo e non lo esegue se l'utente ha chiuso l'app dal multitasking);
  3. a mano (pull-to-refresh).
- **Esperimenti (implementati, disattivati di default)** in `Monitor/Probes.swift`, dentro `eventDidReachThreshold`:
  - **HTTPS**: GET alla pagina di test Apple, oppure POST JSON del `DayResult` a un URL configurabile (simula un backend qualsiasi), con semaforo e timeout di 5 s;
  - **notifica locale**: "Soglia superata, apri l'app per sincronizzare". Toccandola, l'app si apre e sincronizza. E' la mitigazione piu' promettente per la latenza.
  - Ogni probe logga "start" ed esito, cosi' si capisce se il processo viene ucciso a meta'.
- ❓ Conseguenza di prodotto: il partner vede "superata" **solo dopo** che l'altro telefono apre l'app (anche dalla notifica) o esegue un BG refresh. Per uno stato giornaliero va bene; per un avviso "in tempo reale" no. Una push al partner partira' poi dal backend, dopo l'upload.

---

## 4. Entitlement, account, TestFlight/App Store

### Entitlement usati dallo spike

| Target | Entitlement |
|---|---|
| App `DuoSpike` | `com.apple.developer.family-controls`, `com.apple.security.application-groups` |
| Estensione `DuoMonitor` | `com.apple.developer.family-controls`, `com.apple.security.application-groups` |

Piu' la background mode `fetch` (Info.plist, non e' un entitlement). Con CloudKit rimosso non servono iCloud ne' Push.

### Verificato (✅)

- **Tabella ufficiale "Supported capabilities (iOS)"** ([link](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)), letta dall'HTML. Colonne: ADP = Developer Program a pagamento, ADEP = Enterprise, Apple Developer = **gratuito**.

  | Capability | ADP | ADEP | Gratuito |
  |---|---|---|---|
  | App groups | ✓ | ✓ | ✓ |
  | Background modes | ✓ | ✓ | ✓ |
  | **Family Controls (development)** (nota: "Development only") | ✓ | – | **–** |
  | Push notifications (per un backend futuro) | ✓ | ✓ | – |

- Un Apple ID gratuito **non basta**: e' Family Controls a richiedere il programma a pagamento. DTS Apple ([thread 803362](https://developer.apple.com/forums/thread/803362), ott 2025): "There's no supported way to use capabilities that aren't listed there" (cioe' nella colonna gratuita). DTS Apple ([thread 764682](https://developer.apple.com/forums/thread/764682)): la capability "should show up if you're a member of a paid team".
- La pagina dell'entitlement dice: "Before submitting your app to the App Store, you must **request permission** to use the entitlement" ([doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls), [modulo](https://developer.apple.com/contact/request/family-controls-distribution), con login).
- DTS Apple ([thread 712870](https://developer.apple.com/forums/thread/712870)): "You can use this entitlement for development but, for distribution, you'll need to apply for access to it." Senza approvazione non si crea un profilo Distribution, quindi niente TestFlight.
- `requestAuthorization(for: .individual)` e' **iOS 16.0+**. L'autorizzazione individuale chiede Face ID/Touch ID; non impedisce di cancellare l'app ne' di uscire da iCloud ([doc](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization(for:)), [WWDC22](https://developer.apple.com/videos/play/wwdc2022/110336/)).
- App Review Guideline **4.10**: "You may not monetize built-in capabilities provided by ... Apple services and technologies, such as ... **Screen Time APIs**." ([guidelines](https://developer.apple.com/app-store/review/guidelines/))

### Riportato (🟡)

- **Una richiesta Distribution per ogni target** che usa Family Controls (app + DeviceActivityMonitor, ed eventuali estensioni Shield/Report): il main approvato ma l'estensione fallisce all'upload; le richieste per le estensioni "approved within an hour" ([thread 701874](https://developer.apple.com/forums/thread/701874), [712870](https://developer.apple.com/forums/thread/712870)). Il DTS Apple dice di non conoscere il processo di approvazione.
- Tempi di approvazione da pochi giorni a 3 settimane, con alcuni casi di mesi. Nessuna conferma di invio ne' stato visibile ([thread 690522](https://developer.apple.com/forums/thread/690522), [701874](https://developer.apple.com/forums/thread/701874)).
- Da iOS 26.4 revocare l'accesso Tempo di utilizzo richiede il codice di Tempo di utilizzo (fonte terza, [techlockdown](https://www.techlockdown.com/articles/ios26-update-screen-time-protected-app-permissions)). Non verificato.

### Per lo sviluppo su due iPhone

- Basta **un** account Developer Program a pagamento: entrambi i device si registrano nel team. Gli Apple ID dei telefoni possono essere qualsiasi.
- Con un account gratuito l'app non si firma: manca Family Controls.

### Da verificare prima della release (❓)

- Che Apple approvi la Distribution per un caso d'uso "individual + condivisione con il partner" e non solo per il controllo parentale. Inviare al backend solo `exceeded` sì/no al giorno (nessun token, nessun nome di app, nessun minuto) e' la scelta piu' difendibile rispetto allo spirito privacy della API ("usage data will be invisible outside of their device", WWDC21). Ma non ho trovato regole esplicite.

---

## Sync: interfaccia `SyncService` (backend rimandato)

La domanda 3 (CloudKit) non e' piu' in ambito. Lo spike isola il backend dietro `App/Sync/SyncService.swift`:

```swift
@MainActor protocol SyncService: AnyObject {
    var backendName: String { get }
    func currentUserId() async throws -> String
    func pairing() async throws -> Pairing?
    func createInvite(displayName: String) async throws -> Invite
    func acceptInvite(code: String, displayName: String) async throws -> Pairing
    func leavePair() async throws
    func upload(_ results: [DayResult]) async throws          // upsert idempotente su (userId, date)
    func fetchPairResults(days: Int) async throws -> [DayResult]
}
```

- **Implementazione dello spike**: `LocalFakeSyncService`. E' tutto in locale (UserDefaults); il partner e' simulato e il suo stato si imposta dalla schermata debug. Si possono simulare latenza e backend offline. Rifiuta l'upload di record di altri utenti, come farebbe un server.
- **Contratto per il backend reale** (qualunque esso sia, condiviso con Android):
  - identita' utente stabile;
  - coppia creata con un codice invito;
  - upsert idempotente di `DayResult {date, userId, threshold, exceeded}` sulla chiave (userId, date); l'app ricalcola dal log e reinvia senza coda;
  - scrittura consentita solo sui propri record;
  - lettura dei record della coppia;
  - push al partner (APNs/FCM) inviata dal server dopo l'upload.
- `DayResult` e' `Codable` e indipendente dalla piattaforma. `date` e' il giorno **locale** dell'utente: con fusi orari diversi nella coppia, il backend non deve ricalcolarlo.

### Nota cross-platform (❓, non approfondita)

- Qualunque framework cross-platform si scelga, la parte Screen Time resta **nativa Swift**: l'estensione `DeviceActivityMonitor` e' un target separato, con `FamilyActivityPicker` in SwiftUI e l'App Group condiviso. Il layer cross-platform parla solo con l'app principale, tramite un modulo nativo che espone autorizzazione, picker, soglia, monitor e log.
- Esiste almeno un wrapper React Native ([kingstinct/react-native-device-activity](https://github.com/kingstinct/react-native-device-activity)). L'ho solo visto nei risultati di ricerca: non l'ho valutato.
- La controparte Android (es. `UsageStatsManager`) non e' stata ricercata.

---

## iOS minimo

| Requisito | Versione | Fonte |
|---|---|---|
| `AuthorizationCenter.requestAuthorization(for: .individual)` | **16.0** | ✅ doc |
| FamilyControls / DeviceActivity (framework) | 15.0 | ✅ doc |
| `DeviceActivityEvent(... includesPastActivity:)` | **17.4** | ✅ doc |

Lo spike ha deployment target **16.0** e usa `#available(iOS 17.4, *)` per `includesPastActivity`. **Per il prodotto consiglio 17.4**: senza, il conteggio dopo un riavvio del monitor cambia in modo poco prevedibile tra versioni (thread 745675).

---

## Rischi

| # | Rischio | Probabilita' | Impatto | Mitigazione |
|---|---|---|---|---|
| R1 | Falsi positivi / over-counting delle soglie (iOS 26.x, 17.6-18.x; 27 ignoto) | **Alta** (confermato da Apple) | **Alto**: un utente "accusato" a torto rovina la dinamica di coppia | Diagnosi a gradini (implementata): eventi sospetti non comunicati o marcati "da confermare". Design tollerante con possibilita' di contestare. Soak test su 26.x e 27. |
| R2 | Approvazione Family Controls Distribution lenta o negata | Media | **Alto** (blocca TestFlight) | Fare la richiesta **subito**, per app ed estensione, descrivendo il caso d'uso individuale. |
| R3 | Latenza: il partner vede lo stato solo dopo l'apertura dell'app o un BG refresh | Alta | Medio | Prodotto "giornaliero", non real-time. Notifica locale dall'estensione (esperimento E2). Push dal backend dopo l'upload. |
| R4 | Jetsam dell'estensione (6 MB) | Media | Medio | Estensione minimale: solo append di una riga. Probe disattivati di default. Niente SDK di terze parti nell'estensione. |
| R5 | Comportamento a mezzanotte, riavvio, telefono spento non documentato | Media | Medio | Il giorno si ricava dal timestamp dell'evento, non dai callback d'intervallo. Test M1-M4. |
| R6 | Cross-platform: la parte Screen Time e' tutta nativa iOS | Certa | Medio (costo) | Modulo nativo con interfaccia stretta; l'estensione resta in Swift. |
| R7 | Guideline 4.10 (non monetizzare Screen Time API) | Da chiarire | Alto per il business | Verificare il modello di monetizzazione prima del design. |
| R8 | Nessun accesso ai minuti reali fuori da `DeviceActivityReport` | Certa | Basso / Medio | Mostrare i minuti all'utente con un'estensione Report (solo UI locale); al partner si condivide solo il booleano. |

---

## Raccomandazione: **GO condizionato**

**Go** perche':
- il monitoraggio della soglia su app scelte dall'utente, con autorizzazione individuale, e' supportato;
- l'architettura estensione → App Group → app → `SyncService` e' robusta, implementata e indipendente dal backend;
- costi e passi per account ed entitlement sono chiari: 99 USD/anno piu' la richiesta Distribution.

**Condizioni** prima di investire nel design:
1. **Soak test di 7 giorni** con la diagnosi dello spike, su almeno un iPhone con **iOS 26.x** e uno con **iOS 27**. Criterio indicativo: nessun evento mancato e falsi positivi ≤ 1 a settimana per utente, oppure falsi positivi riconosciuti dalla diagnosi a gradini. Se i falsi positivi sono frequenti e non rilevabili, il prodotto deve cambiare tono (motivazionale, contestabile) o aspettare il fix Apple.
2. **Richiedere subito la Family Controls Distribution** per app ed estensione.
3. Eseguire gli esperimenti E1-E3: misurare la latenza con la notifica locale e verificare se la rete dall'estensione e' usabile almeno come best-effort.
4. Validare il modello di business rispetto alla Guideline 4.10.

**No-go** se il soak test mostra falsi positivi quotidiani, non distinguibili dalla diagnosi, sulle versioni di iOS target e senza un fix Apple in vista.

---

## Fonti

Documentazione Apple, letta tramite gli endpoint JSON della documentazione e l'HTML della pagina capabilities:
- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
- [com.apple.developer.family-controls](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls) · [FamilyControls](https://developer.apple.com/documentation/familycontrols) · [requestAuthorization(for:)](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization(for:))
- [DeviceActivity](https://developer.apple.com/documentation/deviceactivity) · [DeviceActivityMonitor](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor) · [DeviceActivitySchedule](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule) · [DeviceActivityEvent init(…includesPastActivity:)](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/init(applications:categories:webdomains:threshold:includespastactivity:)) · [startMonitoring](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)) · [MonitoringError](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror)
- [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (4.10)
- WWDC: [Meet the Screen Time API (2021)](https://developer.apple.com/videos/play/wwdc2021/10123/) · [What's new in Screen Time API (2022)](https://developer.apple.com/videos/play/wwdc2022/110336/)

Forum Apple Developer (risposte Apple dove indicato sopra):
- Affidabilita': [809410](https://developer.apple.com/forums/thread/809410) ([pag. 2](https://developer.apple.com/forums/thread/809410?page=2)) · [812472](https://developer.apple.com/forums/thread/812472) · [811305](https://developer.apple.com/forums/thread/811305) · [763542](https://developer.apple.com/forums/thread/763542) · [745675](https://developer.apple.com/forums/thread/745675) · [741117](https://developer.apple.com/forums/thread/741117) · [721945](https://developer.apple.com/forums/thread/721945) · [757722](https://developer.apple.com/forums/thread/757722)
- Estensione, rete, notifiche e memoria: [724649](https://developer.apple.com/forums/thread/724649) · [727017](https://developer.apple.com/forums/thread/727017) · [749263](https://developer.apple.com/forums/thread/749263) · [735454](https://developer.apple.com/forums/thread/735454) · [823431](https://developer.apple.com/forums/thread/823431) · [827783](https://developer.apple.com/forums/thread/827783) · [818297](https://developer.apple.com/forums/thread/818297)
- Entitlement e account: [712870](https://developer.apple.com/forums/thread/712870) · [690522](https://developer.apple.com/forums/thread/690522) · [701874](https://developer.apple.com/forums/thread/701874) · [803362](https://developer.apple.com/forums/thread/803362) · [764682](https://developer.apple.com/forums/thread/764682)

Fonti terze, usate solo come indizio: [HabitDoom (iOS 27)](https://habitdoom.com/blog/wwdc-2026-screen-time-wishlist) · [techlockdown (iOS 26.4)](https://www.techlockdown.com/articles/ios26-update-screen-time-protected-app-permissions) · [9to5Mac (iOS 27 parental controls)](https://9to5mac.com/2026/09/14/heres-whats-new-with-parental-control-features-in-ios-27-ipados-27-and-macos-27/).

Limiti della ricerca:
- Le pagine del forum mostrano solo mese e anno e possono nascondere commenti dietro "Load more".
- Per iOS 27 non ho trovato release note specifiche su DeviceActivity.
- Le fonti terze non sono verificate.
