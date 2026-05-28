# RENDER Suite — Dokumentasjon

**Versjon:** 1.24 (BETA)
**Dato:** 2026-05-29
**© ENSAMBLE AS** — kontakt: victoria@ensamble.no

> Se [`CHANGELOG.md`](CHANGELOG.md) for full historikk over endringer.

---

## 1. Hva er RENDER Suite?

En verktøypakke for Premiere Pro som automatiserer prosessen med å legge **markers
på multicam-klipp** basert på timecodes hentet fra Teams-meldinger.

Pakken består av to selvstendige verktøy som jobber sammen:

| Verktøy | Type | Funksjon |
|---|---|---|
| **TeamsToCSV** | macOS app (SwiftUI) | Konverterer Teams-screenshots til CSV-fil via OCR |
| **Multicam Markers** | Premiere CEP-plugin (HTML/JS/ExtendScript) | Leser CSV-en og skriver markers på multicam-klipp |

---

## 2. Bruker-workflow

```
   ┌─────────────────┐      ┌──────────────────┐      ┌─────────────────────┐
   │ Teams-chat med  │      │   TeamsToCSV     │      │  Premiere-plugin    │
   │  klokkeslett og │ ───▶ │  (OCR av PNG)    │ ───▶ │  (markers på klipp) │
   │  kommentarer    │      │   → .csv-fil     │      │                     │
   └─────────────────┘      └──────────────────┘      └─────────────────────┘
       screenshot              drag-and-drop                  Window →
                                                            Extensions
```

1. **Brukeren tar screenshots** av Teams-chatten (logg med klokkeslett + kommentarer)
2. **TeamsToCSV** OCR-leser screenshotene og produserer en `.csv`-fil
3. **Premiere-pluginen** importerer CSV-en og legger markers på riktig multicam-klipp

---

## 3. Filstruktur

```
plugin/
├── manifest.xml              ← CEP extension manifest (Premiere kobling)
├── host.jsx                  ← ExtendScript (kjører i Premiere-prosessen)
├── index.html                ← Plugin-panelet (HTML/CSS/JS)
├── 2026-05-27.csv            ← Eksempel-CSV
│
├── TeamsToCSV/
│   ├── main.swift            ← Hele SwiftUI-appen (~800 linjer)
│   ├── build.sh              ← Build-script (swiftc + .app-bundling)
│   ├── generate_icon.py      ← App-ikon generator
│   ├── AppIcon.icns          ← Ferdig app-ikon
│   └── TeamsToCSV.app/       ← Bygd app (output)
│
├── docs/
│   ├── DOKUMENTASJON.md      ← Denne filen
│   └── PROBLEM-RAPPORT.md    ← Rapport om feilsøking 27. mai
│
└── dist/
    ├── RENDER-MulticamMarkers-v3.zip  ← Plugin alene
    ├── TeamsToCSV-v1.zip              ← TeamsToCSV alene
    └── RENDER-Suite-v1.zip            ← Begge i én pakke (anbefalt)
```

---

## 4. Premiere-plugin (Multicam Markers)

### 4.1 Teknologi

Adobe CEP (Common Extensibility Platform) v7.0. Et CEP-panel er essensielt
et Chromium-vindu (CEF) inni Premiere som kommuniserer med Premiere via
ExtendScript (en gammel ECMAScript 3-variant).

### 4.2 Komponenter

| Fil | Hva |
|---|---|
| `CSXS/manifest.xml` | Registrerer extensionen, peker på HTML + JSX |
| `client/index.html` | Hele UI-en (CSS + JS i samme fil) |
| `client/lib/CSInterface.js` | Adobes bro mellom panel-JS og ExtendScript (~42 KB) |
| `host/host.jsx` | ExtendScript-funksjoner som kalles via `evalScript` |

### 4.3 ExtendScript-funksjoner (host.jsx)

```javascript
getMulticamClips()              // Returnerer alle klipp i prosjektet som JSON
addMarkersToClip(id, json, startTC, fps)  // Skriver markers på et klipp
clearMarkersOnClip(id)          // Fjerner alle markers
```

### 4.4 Brukerflyt (3 steg)

| Steg | Hva |
|---|---|
| **1: CSV** | Last opp .csv (drag-and-drop). Forhåndsvisning som tabell. |
| **2: KLIPP** | Velg multicam-klipp (med søkefelt for filtrering) |
| **3: SEND** | Sett Start-TC + FPS manuelt. Klikk "Skriv markers". |

### 4.5 CSV-format

```
HH:MM:SS:FF,Kommentar
09:15:00:00,Sending starter
09:23:45:00,Reklame
```

Også støttet (mindre presisjon):

| Format | Tolkning |
|---|---|
| `HH:MM:SS` | Sekund-presisjon |
| `HH:MM` | Minutt-presisjon |
| `HH.MM` | Teams-stil minutt-presisjon |
| `HH.MM.SS` | Teams-stil sekund-presisjon |

CSV-en parses i `index.html` (`parseCSV()`), og hver linje konverteres til
frames via `tcToFrames()` i `host.jsx`. Posisjonen på klippet beregnes som
`(markerTC - startTC) / fps` sekunder.

### 4.6 Hvorfor manuell Start-TC + FPS?

Multicam-klipp i Premiere er virtuelle sequence-containere, ikke vanlige
media-clips. ExtendScript-APIene `getFootageInterpretation()` og
`item.startTime` returnerer henholdsvis `frameRate: 0` og `undefined` for
multicam. Auto-detect er derfor ikke pålitelig.

Brukeren oppgir manuelt:
- **Start-TC** = klippets wall-clock startpunkt (f.eks. `09:00:00:00`)
- **FPS** = klippets framerate (typisk 25 eller 50 for NRK-prosjekter)

### 4.7 Diagnostikk

Hvis pluginen feiler ved henting av klipp, vises en `🔧 Kjør diagnostikk`-knapp
som kjører 10 tester (basis ExtendScript, app-objekt, prosjekt åpent, JSON-funk,
iterasjon, etc.) — for å isolere feil.

---

## 5. TeamsToCSV (macOS-app)

### 5.1 Teknologi

SwiftUI-app (~800 linjer), kompilert med `swiftc` direkte (ikke Xcode).
Apple Silicon-only (arm64).

### 5.2 OCR-motorer

| Motor | Hvor | Når brukes |
|---|---|---|
| **Tesseract (norsk)** | Ekstern binær via Homebrew | Anbefalt — best på æ/ø/å |
| **Apple Vision** | Innebygd `Vision`-framework | Hvis Tesseract ikke installert |

### 5.3 Hva appen gjør (forenklet)

```
1. Bruker drar PNG inn (eller klikker for å velge)
2. Bildet leses via CGImageSource (full oppløsning, ingen re-encoding)
3. OCR kjøres på bildet → liste med tekst-linjer
4. parseTeamsLines() finner alle HH:MM-mønstre og kobler dem til
   tilhørende kommentar (samme linje eller neste)
5. cleanComment() stripper:
   - Navn-prefikser (f.eks. "Håken Bolstad")
   - Dato-prefikser (f.eks. "15/5.")
   - Teams UI-noise ("Translate", "Edited")
   - Ledende kommaer, anførselstegn, etc.
6. CSV skrives til disk (default: ved siden av PNG)
7. (Valgfritt) Også PDF og/eller XLSX-eksport
```

### 5.4 Innstillinger (UserDefaults-basert, persistent)

- **OCR-motor:** Tesseract (norsk) eller Apple Vision (radio-cards)
- **Fallback:** bruk Apple Vision hvis Tesseract feiler
- **Lagringsplassering:** ved siden av PNG, eller egen mappe
- **Eksportformater:** CSV (alltid), PDF (toggle), XLSX (toggle)

### 5.5 Funksjoner i appen (per v1.24)

- **PNG-thumbnail** i hver fil-rad (44×44, retina-skarp)
- **Quick Look på filnavn-klikk** — verifiserer OCR mot kilden
- **Duplikat-deteksjon:** SHA256-hash skipper allerede-lastet PNG
- **"Slå sammen alle til én CSV":** kombinerer flere filer, sorterer på
  dato + timecode (knappen dukker opp når 2+ filer er lastet)
- **Inline editing:** klikk "Rediger" på en fil-rad for å endre rader,
  slette rader, eller legge til/endre NOTE-felt
- **"Kanskje kuttet"-varsel:** rød pill ved siden av meldinger som ser
  ut til å være avkappet midt i en setning

### 5.6 Auto-update (v1.14+)

Appen sjekker `api.github.com/repos/viavicdev/plugin-markers/releases/latest`
ved oppstart. Hvis det finnes en nyere versjon enn `appVersionLabel`,
vises et rødt banner med "Oppdater nå"-knapp som:

1. Laster ned zip-en fra release-asseten
2. Pakker ut, finner `TeamsToCSV.app` rekursivt
3. Skriver et bash-script til `/tmp` som swapper appen og restarter
4. Quitter selv → script kjører → ny app åpnes

### 5.7 Personvern

- 100% lokal kjøring — ingen API-kall (utenom GitHub-update-sjekk), ingen telemetri
- Source-PNG aldri modifisert (leses via `CGImageSource`, aldri skrives)
- PDF/XLSX skrives kun til disk, ikke til skyen
- Auto-update gjør ETT HEAD-call til GitHub API ved oppstart

---

## 6. Build & distribusjon

### 6.1 Bygge TeamsToCSV

```bash
cd TeamsToCSV
./build.sh
```

Stegene i `build.sh`:
1. `python3 generate_icon.py` → lager `AppIcon.icns`
2. `swiftc -O -parse-as-library` → kompilerer SwiftUI-appen
3. Bygger `.app`-bundle med Info.plist
4. Ad-hoc-signerer med `codesign --force --deep --sign -`
5. Registrerer i LaunchServices

### 6.1b Bygge + publisere ny release (`release.sh`)

For å pushe en ny versjon til alle brukere automatisk:

```bash
./release.sh v1.25                          # standard release-tekst
./release.sh v1.25 "Fikser noten-bug"       # med egen tekst
```

Stegene:
1. Sjekker at `gh` er autentisert + working tree er ren
2. Bumper `appVersionLabel` i `main.swift` til ny versjon
3. Bygger TeamsToCSV-appen
4. Zipper med `ditto -c -k --sequesterRsrc --keepParent` (riktig macOS-format)
5. Committer versjons-bump, tagger, pusher
6. `gh release create` med zip-en som asset

**Krav (én gang):** `brew install gh && gh auth login`.

**For ekte distribusjon med signering:** Updater-appen bygges separat
i `Updater/` med:

```bash
cd Updater && ./build.sh
codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: Victoria Haugnes (25442KK49Q)" \
    "RENDER Markers Oppdaterer.app"
xcrun notarytool submit /tmp/notarize.zip --keychain-profile AC_PASSWORD --wait
xcrun stapler staple "RENDER Markers Oppdaterer.app"
```

### 6.2 Bygge dist-pakker

Tre forskjellige distribusjonspakker finnes i `dist/`:

| Pakke | Innhold | Bruk |
|---|---|---|
| `RENDER-MulticamMarkers-v3.zip` | Bare Premiere-plugin | Hvis bruker ikke trenger TeamsToCSV |
| `TeamsToCSV-v1.zip` | Bare TeamsToCSV-appen | Hvis plugin allerede er installert |
| `RENDER-Suite-v1.zip` | **Begge + smart installer** | Anbefalt for nye brukere |

Hver pakke har:
- `install.command` — bash-script som installerer alt
- `LES-MEG.txt` — bruksanvisning
- (`FAQ.txt` i Suite-pakka)

### 6.3 install.command (Suite-versjonen) gjør:

1. Fjerner macOS quarantine-flag fra pakka (`xattr -cr`)
2. Aktiverer PlayerDebugMode for CSXS 9–13
3. Kopierer plugin til `~/Library/Application Support/Adobe/CEP/extensions/`
4. Kopierer TeamsToCSV.app til `/Applications/`
5. Sjekker om Tesseract finnes → tilbyr å installere via Homebrew
6. Sjekker om Homebrew finnes → tilbyr å installere fra brew.sh

Alle steg er interaktive (krever bruker-bekreftelse for installasjoner).

---

## 7. Krav

| Komponent | Minimum |
|---|---|
| macOS | 12 (Monterey) eller nyere |
| Mac-arkitektur | Apple Silicon (M1/M2/M3/M4) for TeamsToCSV. Intel støttet for plugin alene. |
| Adobe Premiere Pro | 2024 (v24) eller nyere — testet på 26.2.2 |
| Disk | ~25 MB (alt inkludert) |

---

## 8. Kjente begrensninger

1. **Multicam start-TC og FPS** må fylles inn manuelt — auto-detect funker
   ikke pga. Premieres API-design for multicam.
2. **OCR-kvalitet** varierer med fontstørrelse og bildekvalitet i Teams-screenshots.
   Tesseract er generelt bedre enn Apple Vision på norske tegn.
3. **TeamsToCSV-appen er Apple Silicon-only.** Intel-Macer kan bruke pluginen,
   men må generere CSV manuelt eller på annen vei.
4. **Premiere 26+ mangler innebygd JSON** i ExtendScript-engineen — vi har
   lagt inn polyfill, men dette er ikke offisielt dokumentert hos Adobe.
5. ~~Apper er ad-hoc-signert, ikke Apple-signert.~~ **(Løst i v1.24)**
   Apper signeres nå med Developer ID + notariseres + staples — ingen
   Gatekeeper-advarsel.

---

## 9. Fremtidig arbeid

- [ ] First-run wizard i TeamsToCSV.app (slipper Terminal helt)
- [ ] Bundle Tesseract statisk i appen (slipper Homebrew)
- [ ] Auto-detect Start-TC for multicam via XMP metadata
- [ ] AI-vision via Claude/GPT API (valgfritt, opt-in) for bedre OCR
- [x] ~~Apple Developer-signering~~ — gjort i v1.24
- [x] ~~Auto-update-mekanisme~~ — gjort i v1.14, første release v1.24
- [ ] Windows-støtte (Premiere CEP funker på Windows, men TeamsToCSV må re-skrives)
- [ ] Integrasjon: én knapp i pluginen som åpner TeamsToCSV med ferdig screenshot
- [ ] Drag-out CSV-fil fra appen til Finder/Premiere
- [ ] Reordering av rader i edit-modus
- [ ] Søk/filter i radene innenfor en fil

---

## 10. Lisens og opphavsrett

© ENSAMBLE AS, 2026. Alle rettigheter forbeholdt.

CSInterface.js: © Adobe Systems Incorporated (inkludert i CEP SDK).
JSON-polyfill: basert på Douglas Crockfords json2.js (public domain).
Tesseract: Apache 2.0-lisens.
