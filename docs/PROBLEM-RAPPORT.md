# Problem-rapport — 27. mai 2026

**Prosjekt:** RENDER Suite (Multicam Markers + TeamsToCSV)
**Dato:** 2026-05-27
**Forfatter:** Claude (utviklingsassistent)
**Status:** Alle 10 problemer løst og verifisert ✓

---

## Sammendrag

I løpet av en intensiv utviklings- og testsesjon avdekket og løste vi 10
distinkte problemer. Fire av dem var avgjørende for at pluginen i det hele
tatt skulle fungere på sluttbrukerens Mac, og to var subtile Premiere-
spesifikke API-issues vi måtte reverse-engineere oss frem til.

Den vanskeligste å finne var #6 (manglende JSON i Premiere 26+) som krevde
strukturert diagnostikk-arbeid for å isolere.

---

## Problem 1: Plugin viste blank/sort panel

**Symptom:** Pluginen åpnet, men innholdsområdet var helt sort.

**Rotårsak:** `index.html` brukte `var cs = new CSInterface()` på linje 477,
men `<script src="CSInterface.js">` ble lastet på linje 772 — *etter*
hovedskripten. I tillegg pekte script-tag-en på `https://localhost/CSInterface.js`
som ikke fantes. JS-en crashet med `ReferenceError` umiddelbart, ingenting
ble rendret.

**Løsning:**
1. Hentet en lokal kopi av `CSInterface.js` fra en eksisterende Premiere-installasjon
2. La den i `client/lib/CSInterface.js`
3. Flyttet `<script src>` + mock-fallback til *før* hovedskripten i index.html

**Lærdom:** Sjekk script-rekkefølge nøye i CEP-paneler. CEF gir ingen
fornuftige feilmeldinger ved JS-crash.

---

## Problem 2: CSV-format matchet ikke Premieres timecode-format

**Symptom:** Eksempel-CSV-en brukte `19.00,Sending starter` (Teams-stil),
men Premiere's multicam-TC bruker `HH:MM:SS:FF`-format.

**Rotårsak:** Forvirring rundt hvilket format som burde være "kanonisk"
for sluttbrukeren.

**Løsning:**
- Oppdatert eksempel-CSV til `09:00:00:00,...`-format
- Beholdt fortsatt støtte for alle gamle formater (`HH:MM:SS`, `HH:MM`, `HH.MM`, `HH.MM.SS`) i `tcToFrames()` for bakoverkompatibilitet
- Dokumentert formatene i hjelpemodalen

---

## Problem 3: Bare én marker dukket opp på multicam-klippet

**Symptom:** Brukeren sendte 9 markers — bare én ble synlig på klippet.

**Rotårsak (kompleks):** Markers ble *faktisk* lagt til (debug viste
`markers før: 54 → etter: 63`), men alle havnet på samme posisjon
`00:00:00:00` på klippet. Visuelt så det ut som én marker.

**Hvorfor alle stacket:** `getClipFPS()` returnerte `0` for multicam-klipp
(Premieres API `getFootageInterpretation()` returnerer ikke frameRate for
multicam). `getClipStartTC()` returnerte `undefined` av samme grunn.
Resultatet: `seconds = offsetFrames / 0 = NaN`. `createMarker(NaN)`
clamper til posisjon `0`.

**Løsning:**
- Lagt til manuelle input-felter for **Start-TC** og **FPS** på steg 3
- `addMarkersToClip()` aksepterer nå disse parameterne, fallback til
  auto-detect, fallback til 25 fps
- Bruker oppgir manuelt for hvert prosjekt

**Lærdom:** Premiere ExtendScript-API behandler multicam-klipp som
spesialtilfeller — auto-detect er ikke å stole på.

---

## Problem 4: Debug-meldinger viste fps=0 og startTC=undefined

**Symptom:** Diagnose-output viste `fps: 0`, `startTC: NaN:NaN:NaN:NaN`,
`startTCticks: undefined`.

**Rotårsak:** Samme som #3 — Premieres multicam-API mangler properties
som vanlige clips har.

**Løsning:** Se #3.

---

## Problem 5: Distribusjon manglet CSInterface.js → mock-data på andre Mac

**Symptom:** Pluginen viste "SYNMAP_DAG1", "SYNMAP_DAG2", "SYNMAP_DAG3"
i kliplisten på en kollegas Mac — falske eksempel-klipp.

**Rotårsak:** Dist-pakka (`RENDER-MulticamMarkers.zip`) inneholdt ikke
`client/lib/CSInterface.js`. På den andre Macen var derfor `CSInterface`
udefinert, og mock-fallback-en i index.html aktiverte:

```javascript
if (typeof CSInterface === "undefined") {
  // ... returnerte falske eksempel-klipp
}
```

**Løsning:**
- La til `CSInterface.js` i dist-pakka
- Forbedret `install.command` med `xattr -cr` for quarantine-fjerning
- Bygd nytt zip-arkiv og distribuert

**Lærdom:** Ha en sanity-check-script som verifiserer at alle nødvendige
filer er i dist-pakka før den distribueres.

---

## Problem 6: Premiere 26.2.2 mangler innebygd JSON ← VANSKELIGSTE

**Symptom:** Alle `evalScript`-kall til `getMulticamClips()` returnerte
"EvalScript error.", men `1+1` og enkle direktekall fungerte.

**Diagnose-prosess:**
1. Først mistenkte vi at host.jsx var korrupt → verifiserte med `wc -l`
   og `head/tail` på andre Mac → fil var identisk med vår
2. Mistenkte quarantine-flagg → kjørte `xattr -cr` → ingen endring
3. Mistenkte PlayerDebugMode → bekreftet CSXS 9–12 satt
4. Mistenkte race condition → la til auto-retry → fortsatt feil
5. Bygde **10-trinns diagnostikk-knapp** i pluginen som kjørte ulike
   ExtendScript-kall isolert. Resultatet pekte rett på problemet:

```
✓ 1: Basis ExtendScript: 2
✓ 2: helloTest(): hello world          ← funksjoner i host.jsx kjører
✗ 3: helloTestJSON(): EvalScript error. ← KRASJER på JSON.stringify!
✓ 4: app.version: 26.2.2
✓ 5: numItems: 3
✓ 6: item[0].name: 00_Materiale
...
```

**Rotårsak:** Adobe har byttet ExtendScript-engineen i Premiere 26+ og
fjernet den innebygde JSON-implementeringen. ExtendScript er offisielt
ES3, og JSON kom i ES5 — så det er "lovlig" å fjerne, men ingenting i
Adobes dokumentasjon advarer om dette.

**Løsning:** Lagt inn en JSON-polyfill (basert på Crockfords json2.js)
øverst i host.jsx, som definerer `JSON.stringify` og `JSON.parse` hvis
de mangler. Polyfillen er ES3-kompatibel og påvirker ikke eldre
Premiere-versjoner (kun aktiv hvis `typeof JSON !== "object"`).

**Lærdom:** Adobes ExtendScript-dokumentasjon er ikke alltid oppdatert
mot faktisk implementasjon. Bygg defensivt med polyfills for ES5+
features.

---

## Problem 7: Polyfill med ødelagt regex krasjet hele host.jsx

**Symptom:** Etter polyfill-installasjonen krasjet *alt* — selv `1+1`
returnerte "EvalScript error.".

**Rotårsak:** Den første polyfill-versjonen vi prøvde (Crockfords original)
inneholdt en regex med unicode-control-characters:

```javascript
var rx_escapable = /[\\\" --­؀-؄܏...]/g;
```

Disse spesialtegnene fikk ExtendScript-parser til å feile, og hele
host.jsx ble ikke lastet. Alle evalScript-kall feilet derfor, ikke
bare de som brukte JSON.

**Løsning:** Erstattet med en enklere, character-by-character polyfill
uten problematisk regex. Verifisert at den parser og roundtripper
korrekt før distribusjon (Node `--check` + `JSON.stringify` test).

**Lærdom:** Test JSON-polyfill ISOLERT før den limes inn i prosjekt-
koden. Sjekk syntax med en JS-parser (Node) før distribusjon.

---

## Problem 8: TeamsToCSV.app "er skadet" på andre Mac

**Symptom:** macOS Gatekeeper sa "TeamsToCSV.app is damaged and can't
be opened" på kollegas Mac.

**Rotårsak:** macOS legger automatisk `com.apple.quarantine` extended
attribute på alle filer som lastes ned fra internett. Usignerte apper
med quarantine viser "damaged" istedenfor den vanlige "uidentifisert
utvikler"-meldingen.

**Løsning:**
1. Ad-hoc-signerte TeamsToCSV.app med `codesign --force --deep --sign -`
2. Oppdatert `install.command` med `xattr -cr "."` som første steg
   (fjerner quarantine fra hele installasjonsmappa)
3. Dokumentert i FAQ.txt hvordan brukeren manuelt kan kjøre `xattr -cr`

**Lærdom:** Ad-hoc-signering (`-`) gir ikke ekte trust, men forhindrer
"damaged"-meldingen. For "uidentifisert utvikler" → bruker må fortsatt
høyreklikke → Åpne første gang.

---

## Problem 9: OCR-kvalitet — Apple Vision sliter med norske tegn

**Symptom:** CSV-output inneholdt feil som "Hoken" (skal være "Håken"),
"Kjorer" (skal være "Kjører"), "0g" (skal være "og"), og mojibake som
"pÃ¤" (skal være "på").

**Rotårsak (todelt):**
1. **Reelle OCR-feil:** Apple Vision er ikke optimalisert for norsk
   tekst — mangler diakritiske tegn (å→a) eller forveksler dem (å→ä).
2. **Mojibake-illusjon:** Filene var korrekt UTF-8 — Excel åpnet dem
   som Latin-1 og viste UTF-8-bytes som rare tegn.

**Løsning:**
- La til **Tesseract-motor** som alternativ (norsk språkmodell `nor`,
  betydelig bedre på æ/ø/å)
- La til **post-OCR-cleaning** i `parseTeamsLines()`:
  - Stripper navn-prefikser ("Håken Bolstad")
  - Stripper dato-prefikser ("15/5.")
  - Stripper UI-noise ("Translate", "Edited")
  - Look-ahead til neste linje hvis kommentar bare er navn/dato
- Dokumentert UTF-8-issue i FAQ ("åpne i TextEdit, ikke Excel")

**Lærdom:** Apple Vision er rask men ikke best på norsk. Tesseract med
`nor`-pakke er gull. Bilde-preprocessing (skalering, kontrast) hjelper
ikke nok til å rettferdiggjøre kompleksiteten.

---

## Problem 10: Race condition — loadClips før host.jsx lastet

**Symptom:** Første gang pluginen åpnet på den andre Mac (Premiere
26.2.2), feilet `getMulticamClips()` med "ExtendScript-feil". Men
klikket man "↺ Oppdater" 1-2 sekunder senere, fungerte det.

**Rotårsak:** CEP laster `ScriptPath` asynkront. På treg Mac /
Premiere 26.2.2 tar dette lengre tid enn på utviklingsmaskinen.
Pluginens `loadClips()` kjørte umiddelbart når steg 2 åpnet — før
host.jsx var ferdig lastet.

**Løsning:** Lagt til **auto-retry** i `loadClips(retryCount)` — opptil
3 forsøk med eksponentiell backoff (500ms, 1000ms, 1500ms). Viser
"Laster (forsøk N)..." underveis.

**Lærdom:** ExtendScript-laste-tid er ikke garantert. Alle førstegangs-
kall til host.jsx-funksjoner bør ha retry-logikk.

---

## Verktøy og teknikker som hjalp diagnostikken

1. **`xattr` for quarantine-debug** — `xattr -cr` og `xattr <fil>` for
   å se/fjerne flagg.
2. **Innebygd diagnostikk-knapp i pluginen** — kunne sendes til
   sluttbruker, kjøre 10 tester, vise nøyaktig hvor feilen oppstod.
3. **Defensiv error handling** — try/catch rundt hver enkelt item-tilgang
   i `scanBin()`, så én korrupt item ikke crasher hele scanningen.
4. **Sanity-check-script** før hver dist-bygg — verifiserer at alle
   filer er på plass, polyfill kompilerer, app er signert, etc.
5. **Node `--check`** for å verifisere JS-syntax før vi limte inn i host.jsx.

---

## Statistikk

| Måltall | Verdi |
|---|---|
| Antall problemer løst | 10 |
| Antall zip-versjoner bygd | 6 |
| Linjer kode endret | ~600 (host.jsx + index.html + main.swift) |
| Tid investert | ~4 timer aktiv utvikling |
| Antall kollega-tester | 7 (på andre Mac) |
| Kritisk insight | Premiere 26+ mangler JSON.stringify |

---

## Sluttilstand

✅ Pluginen fungerer på Premiere 26.2.2 (M-serie Mac)
✅ Pluginen fungerer på utviklingsmaskinen (tidligere Premiere-versjon)
✅ TeamsToCSV-appen installerer + kjører + produserer korrekt CSV
✅ Tesseract auto-install via installer-script
✅ Komplett distribusjonspakke (`RENDER-Suite-v1.zip`, 246 KB)
✅ Dokumentasjon + FAQ skrevet for ikke-tekniske brukere

---

**Konklusjon:** Et lærerikt prosjekt med flere subtile feilkilder. Den
viktigste leksjonen er at Adobes nyere Premiere-versjoner har endret
ExtendScript-engineen uten god dokumentasjon — og JSON-polyfill er nå
et must for any CEP-utvidelse som skal fungere på Premiere 26+.

© ENSAMBLE AS — victoria@ensamble.no
