# SPIKE: fattibilita' di un'app di coppia con soglia giornaliera sui social

Data ricerca: 7 novembre 2026. Il codice compila (CI: Xcode 26.3, deployment target iOS 16.0) ma **non e' ancora stato eseguito su un device**. Le conclusioni "da verificare" vanno chiuse con il piano di test del [README](README.md#4-piano-di-test).

Legenda:
- ✅ **Verificato**: documentazione Apple o risposta di un ingegnere Apple (DTS / Frameworks Engineer) sui forum.
- 🟡 **Riportato**: piu' sviluppatori sui forum Apple, senza conferma Apple.
- ❓ **Ipotesi**: mio ragionamento o comportamento atteso, non documentato. Da verificare sul device.

---

## TL;DR

| Domanda | Risposta breve |
|---|---|
| 1. `eventDidReachThreshold` e' affidabile? | **Funziona, ma non e' affidabile al 100%.** Apple ha confermato un bug di **falsi positivi** su iOS 26.2+ ("known issue ... being investigated") e in passato ha riconosciuto un over-counting su iOS 17/18 senza workaround. A mezzanotte i callback arrivano **al primo utilizzo dopo** il confine, non alle 00:00. Sul riavvio non c'e' documentazione: va testato. |
| 2. Rete / CloudKit dall'estensione? | **Non in modo affidabile.** Apple: il ciclo di vita finisce quando il metodo sincrono ritorna, e una richiesta asincrona verra' probabilmente interrotta. Workaround suggerito da Apple: bloccare con un timeout di ~3 s. Limite memoria ~6 MB. Il **fallback App Group + sync dall'app e' la scelta giusta** (implementato); la scrittura diretta e' un esperimento attivabile. |
| 3. Due Apple ID via CloudKit (CKShare zone-wide)? | **Si', e' il caso d'uso documentato** (`CKShare(recordZoneID:)`, iOS 15+; il sample Apple usa due device con account iCloud diversi). Implementato con il record `DayResult`. |
| 4. Entitlement / account | Serve l'**Apple Developer Program a pagamento**: con un Apple ID gratuito Family Controls e CloudKit non sono disponibili (verificato sulla tabella Apple). Lo sviluppo e' immediato; per TestFlight/App Store serve una **richiesta separata "Family Controls (Distribution)"**, in pratica una per ogni bundle ID (app ed estensione). |
| iOS minimo | **iOS 16.0** (`requestAuthorization(for: .individual)`). **Consigliato 17.4** per controllare `includesPastActivity`. |
| **Raccomandazione** | **GO condizionato.** La fattibilita' tecnica c'e'. Il rischio principale e' l'affidabilita' delle soglie su iOS 26.x, che Apple non controlla ancora. Il design deve tollerare falsi positivi. Prima del design: soak test di 7 giorni su 2 telefoni (vedi sotto). |

---

## 1. Affidabilita' di `eventDidReachThreshold` per una soglia giornaliera

### Come funziona (✅ documentazione Apple)

- `DeviceActivityEvent`: "An application's extension receives a callback once the combination of specified applications, categories, and webDomains have been in use longer than the event's threshold **within the activity's scheduled interval**." Con uno schedule 00:00-23:59 `repeats: true`, il conteggio e' quindi per giorno. ([DeviceActivityEvent init](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/init(applications:categories:webdomains:threshold:includespastactivity:)))
- `includesPastActivity` (**iOS 17.4+**): stabilisce se l'uso precedente all'avvio del monitoraggio conta per la soglia. Esempio Apple: `startMonitoring` alle 13:30 con schedule 13:00-14:00. Per una soglia "giornaliera" vera serve `true`: se l'utente cambia soglia alle 15:00, l'uso dalle 00:00 conta comunque.
- `startMonitoring`: sovrascrive schedule ed eventi di un'attivita' gia' monitorata. Puo' lanciare un errore se ci sono troppe attivita' o se sono troppo ravvicinate. L'estensione "may begin receiving callbacks as soon as the system calls this method if the activity's scheduled interval is ongoing". ([startMonitoring](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)))
- Errori possibili: `excessiveActivities`, `intervalTooLong`, `intervalTooShort`, `invalidDateComponents`, `unauthorized`. ([MonitoringError](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror))
- Le app scelte con `FamilyActivityPicker` arrivano come **token opachi**: l'app non conosce i nomi delle app scelte. ([WWDC21 "Meet the Screen Time API"](https://developer.apple.com/videos/play/wwdc2021/10123/))
- Per condividere dati tra app ed estensione serve un App Group. `print` dell'estensione non compare nel debugger (altro processo): usare `Logger`. Lo dice un Frameworks Engineer Apple. ([thread 721945](https://developer.apple.com/forums/thread/721945))

### Mezzanotte (✅ in parte, ❓ in parte)

- ✅ WWDC21: "These functions will be called **the first time the device is used after** the start and end of my schedule." `intervalDidEnd` / `intervalDidStart` **non** arrivano alle 00:00 esatte, ma al primo utilizzo successivo. ([WWDC21](https://developer.apple.com/videos/play/wwdc2021/10123/))
- ❓ **Conseguenza per il design**: non si puo' "chiudere" il giorno precedente con un callback a mezzanotte. Nello spike il risultato di un giorno si ricava dal log: `exceeded = true` se c'e' un `eventDidReachThreshold` con quella data. Un giorno passato senza evento si considera `false`. Il giorno corrente resta "non superata finora" fino all'evento.
- ❓ Uso a cavallo della mezzanotte (23:50-00:10): dovrebbe dividersi tra i due intervalli. Da verificare (test M1/M2).

### Telefono spento o riavviato (❓ nessuna fonte ufficiale)

- Non ho trovato documentazione Apple ne' risposte Apple sul comportamento dopo un riavvio. In un thread un DTS chiede se il problema avvenga "right after starting monitoring, after a reboot, or after an OS update", segno che il riavvio e' una variabile nota ma non documentata ([thread 809410](https://developer.apple.com/forums/thread/809410)).
- ❓ Ipotesi: le attivita' registrate sono di sistema e persistono (`DeviceActivityCenter.activities`). Dopo il riavvio i callback ripartono al primo utilizzo dopo lo sblocco. Mentre il telefono e' spento non c'e' uso, quindi nulla da contare.
- ❓ Rischio tecnico: prima del primo sblocco dopo il riavvio i file protetti dell'App Group non sono accessibili (protezione dati di default). In pratica l'utente non usa app prima di sbloccare. Da verificare con il test M3 (cerca `ext.init` nel log).

### Bug noti (✅ confermati da Apple, 🟡 riportati)

| Versione iOS | Problema | Fonte | Stato |
|---|---|---|---|
| 26.2 → 26.4 (e segnalazioni su 26.5) | Evento **prematuro**, spesso allo sblocco del mattino o in carica, con 0 minuti in Tempo di utilizzo. Anche l'"App Limit" nativo di iOS risulta colpito. | [thread 809410](https://developer.apple.com/forums/thread/809410), [812472](https://developer.apple.com/forums/thread/812472), [811305](https://developer.apple.com/forums/thread/811305) | ✅ DTS Apple (gen 2026): "This is a known issue that is currently being investigated." Non ho trovato release notes con il fix. |
| 17.6.1 → 18.x | **Over-counting**: soglia di 300 min scattata a 150 min; eventi multipli in pochi ms. | [thread 763542](https://developer.apple.com/forums/thread/763542) | ✅ DTS Apple (dic 2024): "I don't have any info to share about when, or indeed if, that'll be fixed", "I also can't see any sort of reasonable workaround." |
| 17.4 | `includesPastActivity` ha default `false`, mentre prima il comportamento era come `true`: le app esistenti si sono rotte. | [thread 745675](https://developer.apple.com/forums/thread/745675) | 🟡 Nessuna risposta Apple. Nello spike il valore e' **sempre esplicito**. |
| 16.x / 17.x | Callback non chiamato, oppure chiamato piu' volte di seguito. | [thread 741117](https://developer.apple.com/forums/thread/741117), [757722](https://developer.apple.com/forums/thread/757722) | 🟡 Alcuni casi sono errori di configurazione. Lo spike de-duplica (conta il primo evento del giorno) e logga tutti gli eventi. |

### Risposta

Il meccanismo e' quello giusto e funziona per la maggior parte degli utenti. Ma **non e' affidabile al 100%** e la parte inaffidabile e' fuori dal nostro controllo: Apple conferma falsi positivi su iOS 26.2+ e non offre workaround per l'over-counting. Non c'e' modo di verificare i minuti da codice: i dati di utilizzo sono leggibili solo dentro un'estensione `DeviceActivityReport`, che e' sandboxata e non puo' esportarli. Lo segnalano gli sviluppatori in [thread 818297](https://developer.apple.com/forums/thread/818297); non l'ho verificato sulla documentazione.

---

## 2. Rete e CloudKit dall'estensione DeviceActivityMonitor

### Cosa dice Apple (✅)

- Frameworks Engineer Apple, risposta accettata in [thread 724649](https://developer.apple.com/forums/thread/724649) (feb 2023): "DeviceActivityMonitor extensions are intended to be very lightweight and **their lifecycle ends as soon as the synchronous methods you override return**." Una richiesta di rete asincrona verra' quindi probabilmente interrotta. Suggerisce di aprire un enhancement request per callback asincrone e, come workaround, un `DispatchGroup` con `wait(timeout: 3.0)`.
- Non ho trovato documentazione che **vieti** la rete nell'estensione Monitor. Il divieto esplicito riguarda l'estensione Report, secondo i thread degli sviluppatori.

### Cosa riportano gli sviluppatori (🟡)

- Il server riceve "rarely" le POST fatte da `intervalDidEnd`. Con due richieste in sequenza parte solo la prima ([thread 724649](https://developer.apple.com/forums/thread/724649)).
- Limite di memoria dell'estensione **~6 MB**: crash `EXC_RESOURCE`/jetsam, "peggiorato su iOS 26" ([thread 735454](https://developer.apple.com/forums/thread/735454), [823431](https://developer.apple.com/forums/thread/823431), [827783](https://developer.apple.com/forums/thread/827783)).
- CloudKit dall'estensione: **nessuna fonte trovata**, ne' a favore ne' contro.

### Risposta e scelta implementata

- ❓ Ipotesi: tecnicamente si puo' tentare (l'estensione ha entitlement iCloud e il semaforo tiene vivo il processo qualche secondo). Il successo pero' non e' garantito: ciclo di vita, 6 MB, nessuna rete disponibile in quel momento.
- **Strategia principale (implementata)**: l'estensione scrive **solo** una riga nel log JSONL dell'App Group (`events.jsonl`, append, pochi KB). L'app principale calcola i `DayResult` e li sincronizza:
  1. all'apertura o al ritorno in foreground (`scenePhase == .active`);
  2. con `BGAppRefreshTask` (✅ richiede la background mode `fetch`; ❓ iOS decide quando eseguirlo e non lo esegue se l'utente ha chiuso l'app dal multitasking);
  3. alla ricezione di una push silenziosa CloudKit (`CKDatabaseSubscription`): serve al telefono che **riceve**.
- **Esperimento (implementato, disattivato di default)**: `Probes.swift` prova, dentro `eventDidReachThreshold`, una GET HTTPS e un upsert CloudKit del `DayResult`, con semaforo e timeout. Logga "start" ed esito, cosi' si capisce se il processo viene ucciso. Test E1-E4 del README.
- ❓ Conseguenza di prodotto: senza la scrittura diretta, il partner vede "superata" **solo dopo** che l'altro telefono apre l'app o esegue un BG refresh. Per uno stato giornaliero e' accettabile; per una notifica "in tempo reale" no. Possibile mitigazione da provare: una notifica locale dall'estensione ("Hai superato la soglia") che, toccata, apre l'app e fa partire il sync. Non implementata.

---

## 3. Condivisione tra due Apple ID con CloudKit

### Verificato (✅ documentazione Apple)

- `CKShare(recordZoneID:)` e' **iOS 15+**. Le zone custom del database privato hanno di default la capability `zoneWideSharing`. Una zona puo' far parte di **un solo** share. Dopo l'accettazione, i record compaiono in una zona del **database condiviso** del partecipante. ([CKShare init(recordZoneID:)](https://developer.apple.com/documentation/cloudkit/ckshare/init(recordzoneid:)))
- Il sample Apple [Sharing CloudKit data with other iCloud users](https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users) usa proprio **due device con account iCloud diversi**. Con permesso "can make changes" il partecipante aggiunge record che arrivano al proprietario "within seconds".
- Per aprire l'app dal link d'invito serve `CKSharingSupported = YES` nell'Info.plist ([doc](https://developer.apple.com/documentation/bundleresources/information-property-list/cksharingsupported)). L'accettazione arriva a `windowScene(_:userDidAcceptCloudKitShareWith:)`, oppure in `connectionOptions.cloudKitShareMetadata` se l'app non era in esecuzione. In un'app SwiftUI serve un scene delegate esplicito ([doc](https://developer.apple.com/documentation/uikit/uiwindowscenedelegate/windowscene(_:userdidacceptcloudkitsharewith:))). Tutto questo e' implementato.
- In ambiente Development CloudKit crea i record type al primo salvataggio. Per TestFlight/App Store bisogna deployare lo schema in Production.

### Modello implementato

- Il primo utente (**owner**) crea la zona `DuoZone` nel proprio DB privato e un `CKShare` zone-wide. Poi invita il partner con `UICloudSharingController`; c'e' anche un fallback con link pubblico read/write.
- Il partner (**participant**) accetta. Entrambi scrivono nella **stessa zona**: l'owner con `privateCloudDatabase`, il partner con `sharedCloudDatabase` e lo `zoneID` dell'owner.
- Record `DayResult` con ID deterministico `<userId>_<yyyy-MM-dd>`, cosi' l'upsert non richiede query. Campi: `date`, `userId`, `threshold`, `exceeded`, piu' `exceededAt`, `displayName` e `updatedAt` per misurare la latenza. `userId` e' il `recordName` dell'utente CloudKit nel container.
- Lettura con `CKFetchRecordZoneChangesOperation` invece di `CKQuery`, per non dover configurare indici queryable.

### Ipotesi da verificare (❓)

- La `CKDatabaseSubscription` sul DB **privato** dell'owner dovrebbe scattare anche quando il partner scrive nella zona condivisa. Test T4/T6.
- Tutti i dati occupano la quota iCloud dell'owner: trascurabile, pochi byte al giorno.
- Se uno dei due esce da iCloud o rimuove la partecipazione, lo stato si perde: va gestito nel prodotto.

---

## 4. Entitlement, account, TestFlight/App Store

### Verificato (✅)

- **Tabella ufficiale "Supported capabilities (iOS)"** ([link](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)), letta dall'HTML. Colonne: ADP = Developer Program a pagamento, ADEP = Enterprise, Apple Developer = **gratuito**.

  | Capability | ADP | ADEP | Gratuito |
  |---|---|---|---|
  | App groups | ✓ | ✓ | ✓ |
  | Background modes | ✓ | ✓ | ✓ |
  | **Family Controls (development)** (nota: "Development only") | ✓ | – | **–** |
  | **iCloud: CloudKit** | ✓ | ✓ | **–** |
  | Push notifications | ✓ | ✓ | – |

- Un Apple ID gratuito **non basta**. DTS Apple ([thread 803362](https://developer.apple.com/forums/thread/803362), ott 2025): "There's no supported way to use capabilities that aren't listed there" (cioe' nella colonna gratuita). DTS Apple ([thread 764682](https://developer.apple.com/forums/thread/764682)): la capability "should show up if you're a member of a paid team".
- La pagina dell'entitlement `com.apple.developer.family-controls` dice: "Before submitting your app to the App Store, you must **request permission** to use the entitlement" ([doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls), [modulo](https://developer.apple.com/contact/request/family-controls-distribution), con login).
- DTS Apple ([thread 712870](https://developer.apple.com/forums/thread/712870)): "You can use this entitlement for development but, for distribution, you'll need to apply for access to it." Senza approvazione non si crea un profilo Distribution, quindi niente TestFlight.
- `requestAuthorization(for: .individual)` e' **iOS 16.0+**. L'autorizzazione individuale chiede Face ID/Touch ID; non impedisce di cancellare l'app ne' di uscire da iCloud ([doc](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization(for:)), [WWDC22](https://developer.apple.com/videos/play/wwdc2022/110336/)).
- App Review Guideline **4.10**: "You may not monetize built-in capabilities provided by ... Apple services and technologies, such as ... **Screen Time APIs**." ([guidelines](https://developer.apple.com/app-store/review/guidelines/)) Va tenuto presente se il modello di business prevede un abbonamento.

### Riportato (🟡)

- **Una richiesta Distribution per ogni target** che usa Family Controls (app + DeviceActivityMonitor, ed eventuali estensioni Shield/Report): il main approvato ma l'estensione fallisce all'upload; le richieste per le estensioni "approved within an hour" ([thread 701874](https://developer.apple.com/forums/thread/701874), [712870](https://developer.apple.com/forums/thread/712870)). Il DTS Apple dice di non conoscere il processo di approvazione.
- Tempi di approvazione molto variabili: da pochi giorni a 3 settimane, con alcuni casi di mesi. Nessuna conferma di invio ne' stato visibile ([thread 690522](https://developer.apple.com/forums/thread/690522), [701874](https://developer.apple.com/forums/thread/701874)).
- Da iOS 26.4 revocare l'accesso Tempo di utilizzo a un'app richiede il codice di Tempo di utilizzo (fonte terza, [techlockdown](https://www.techlockdown.com/articles/ios26-update-screen-time-protected-app-permissions)). Non verificato.

### Per lo sviluppo su due iPhone

- Basta **un** account Developer Program a pagamento. Entrambi i device si registrano nel team; l'Apple ID iCloud del secondo telefono puo' essere qualsiasi.
- Con un account gratuito l'app non si firma nemmeno: mancano Family Controls, CloudKit e Push.

### Da verificare prima della release (❓)

- Che Apple approvi la Distribution per un caso d'uso "individual + condivisione con il partner" e non solo per il controllo parentale. Inviare una sola informazione aggregata (`exceeded` sì/no al giorno, nessun token, nessun nome di app, nessun minuto) e' la scelta piu' difendibile rispetto allo spirito privacy della API ("usage data will be invisible outside of their device", WWDC21). Ma non ho trovato regole esplicite su questo punto.

---

## iOS minimo

| Requisito | Versione | Fonte |
|---|---|---|
| `AuthorizationCenter.requestAuthorization(for: .individual)` | **16.0** | ✅ doc |
| `CKShare(recordZoneID:)` | 15.0 | ✅ doc |
| FamilyControls / DeviceActivity (framework) | 15.0 | ✅ doc |
| `DeviceActivityEvent(... includesPastActivity:)` | **17.4** | ✅ doc |

Lo spike ha deployment target **16.0** e usa `#available(iOS 17.4, *)` per `includesPastActivity`. **Per il prodotto consiglio 17.4**: senza, il conteggio dopo un riavvio del monitor cambia in modo poco prevedibile tra versioni (thread 745675).

---

## Rischi

| # | Rischio | Probabilita' | Impatto | Mitigazione |
|---|---|---|---|---|
| R1 | Falsi positivi / over-counting delle soglie (iOS 26.2+, 17.6-18.x) | **Alta** (confermato da Apple) | **Alto**: un utente "accusato" a torto rovina la dinamica di coppia | Design tollerante: possibilita' di contestare, niente penalita' automatiche dure; log diagnostico; soak test; controlli di plausibilita' (es. eventi intermedi a 25/50/75% della soglia, scartare la soglia raggiunta prima di N minuti dall'`intervalDidStart`). Da sperimentare. |
| R2 | Approvazione Family Controls Distribution lenta o negata | Media | **Alto** (blocca TestFlight) | Fare la richiesta **subito**, per app ed estensione, descrivendo il caso d'uso individuale. |
| R3 | Latenza di sync: il partner vede lo stato solo dopo l'apertura dell'app o un BG refresh | Alta | Medio | Prodotto "giornaliero", non real-time. Notifica locale dall'estensione (da provare). Esperimento di scrittura diretta su CloudKit (E1-E4). |
| R4 | Jetsam dell'estensione (6 MB) | Media | Medio | Estensione minimale: solo append di una riga. Probe disattivati di default. |
| R5 | Comportamento a mezzanotte, riavvio, telefono spento non documentato | Media | Medio | Il giorno si ricava dal timestamp dell'evento, non dai callback d'intervallo. Test M1-M4. |
| R6 | CloudKit sharing: UX dell'invito, account iCloud assenti, uscita dalla coppia | Media | Medio | Fallback link pubblico (solo spike), discovery manuale della zona. Nel prodotto: stati d'errore chiari. |
| R7 | Guideline 4.10 (non monetizzare Screen Time API) | Da chiarire | Alto per il business | Verificare il modello di monetizzazione prima del design. |
| R8 | Nessun accesso ai minuti reali fuori da `DeviceActivityReport` | Certa | Basso / Medio | Mostrare i minuti all'utente con un'estensione Report (solo UI locale); al partner si condivide solo il booleano. |

---

## Raccomandazione: **GO condizionato**

**Go** perche' tutte e 4 le domande hanno una risposta tecnica positiva o un fallback solido:
- monitoraggio della soglia su app scelte dall'utente con autorizzazione individuale: supportato;
- estensione → App Group → app → CloudKit: architettura robusta e implementata;
- due Apple ID tramite CKShare su una zona: caso documentato da Apple;
- account e entitlement: costi e passi chiari (99 USD/anno + richiesta Distribution).

**Condizioni** prima di investire nel design:
1. **Soak test di 7 giorni** su due iPhone con la versione di iOS piu' diffusa (oggi 26.x), con il piano di test del README. Criterio indicativo: nessun evento mancato e falsi positivi ≤ 1 a settimana per utente. Se i falsi positivi sono frequenti, il prodotto deve cambiare tono (motivazionale, contestabile) o aspettare il fix Apple.
2. **Richiedere subito la Family Controls Distribution** per app ed estensione: i tempi sono imprevedibili ed e' l'unico blocco esterno per TestFlight.
3. Eseguire gli esperimenti E1-E4 per decidere se il sync "quasi real-time" dall'estensione e' praticabile o se il prodotto resta "giornaliero / all'apertura".
4. Validare il modello di business rispetto alla Guideline 4.10.

**No-go** se il soak test mostra falsi positivi quotidiani sulla versione di iOS target senza un fix Apple in vista: un'app di coppia basata su "chi ha superato la soglia" non regge se il dato e' sbagliato.

---

## Fonti

Documentazione Apple, letta tramite gli endpoint JSON della documentazione e l'HTML della pagina capabilities:
- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
- [com.apple.developer.family-controls](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls) · [FamilyControls](https://developer.apple.com/documentation/familycontrols) · [requestAuthorization(for:)](https://developer.apple.com/documentation/familycontrols/authorizationcenter/requestauthorization(for:))
- [DeviceActivity](https://developer.apple.com/documentation/deviceactivity) · [DeviceActivityMonitor](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor) · [DeviceActivitySchedule](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule) · [DeviceActivityEvent init(…includesPastActivity:)](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent/init(applications:categories:webdomains:threshold:includespastactivity:)) · [startMonitoring](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/startmonitoring(_:during:events:)) · [MonitoringError](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror)
- [CKShare init(recordZoneID:)](https://developer.apple.com/documentation/cloudkit/ckshare/init(recordzoneid:)) · [Sharing CloudKit data with other iCloud users](https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users) · [CKSharingSupported](https://developer.apple.com/documentation/bundleresources/information-property-list/cksharingsupported) · [windowScene(_:userDidAcceptCloudKitShareWith:)](https://developer.apple.com/documentation/uikit/uiwindowscenedelegate/windowscene(_:userdidacceptcloudkitsharewith:)) · [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (4.10)
- WWDC: [Meet the Screen Time API (2021)](https://developer.apple.com/videos/play/wwdc2021/10123/) · [What's new in Screen Time API (2022)](https://developer.apple.com/videos/play/wwdc2022/110336/)

Forum Apple Developer (risposte Apple dove indicato sopra):
- Affidabilita': [809410](https://developer.apple.com/forums/thread/809410) · [812472](https://developer.apple.com/forums/thread/812472) · [811305](https://developer.apple.com/forums/thread/811305) · [763542](https://developer.apple.com/forums/thread/763542) · [745675](https://developer.apple.com/forums/thread/745675) · [741117](https://developer.apple.com/forums/thread/741117) · [721945](https://developer.apple.com/forums/thread/721945) · [757722](https://developer.apple.com/forums/thread/757722)
- Estensione, rete e memoria: [724649](https://developer.apple.com/forums/thread/724649) · [735454](https://developer.apple.com/forums/thread/735454) · [823431](https://developer.apple.com/forums/thread/823431) · [827783](https://developer.apple.com/forums/thread/827783) · [818297](https://developer.apple.com/forums/thread/818297)
- Entitlement e account: [712870](https://developer.apple.com/forums/thread/712870) · [690522](https://developer.apple.com/forums/thread/690522) · [701874](https://developer.apple.com/forums/thread/701874) · [803362](https://developer.apple.com/forums/thread/803362) · [764682](https://developer.apple.com/forums/thread/764682)

Fonti terze, usate solo come indizio: [techlockdown (iOS 26.4)](https://www.techlockdown.com/articles/ios26-update-screen-time-protected-app-permissions).

Limiti della ricerca: le pagine del forum possono nascondere commenti dietro "Load more". Non ho letto la pagina 2 del thread 809410. Le date delle fonti terze sono incerte.
