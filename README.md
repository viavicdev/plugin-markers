# RENDER Suite — Prosjektmappe

**Multicam Markers (Premiere-plugin) + TeamsToCSV (macOS-app)**

© ENSAMBLE AS · victoria@ensamble.no

---

## Mappestruktur

```
plugin/
├── README.md                  ← Denne filen
│
├── premiere-plugin/           ← Kildekode for Premiere CEP-pluginen
│   ├── manifest.xml             CEP extension manifest
│   ├── index.html               UI (HTML/CSS/JS, alt i én fil)
│   ├── host.jsx                 ExtendScript som kjører i Premiere
│   └── lib/
│       └── CSInterface.js       Adobes JS↔ExtendScript bro
│
├── TeamsToCSV/                ← Kildekode for macOS-appen
│   ├── main.swift               Hele SwiftUI-appen (~800 linjer)
│   ├── build.sh                 Bygger TeamsToCSV.app fra main.swift
│   ├── generate_icon.py         Genererer app-ikon
│   ├── AppIcon.icns             Ferdig app-ikon
│   ├── AppIcon-1024.png         Kilde-PNG for ikonet
│   ├── AppIcon.iconset/         iconset-mappe (mellomfiler)
│   └── TeamsToCSV.app/          Bygd app (output fra build.sh)
│
├── examples/                  ← Test-data
│   ├── 2026-05-27.csv           Eksempel-CSV med 26 markers
│   └── teams-screenshot-sample.png  Eksempel-screenshot fra Teams
│
├── docs/                      ← Dokumentasjon
│   ├── DOKUMENTASJON.md         Prosjektoversikt og teknisk doc
│   └── PROBLEM-RAPPORT.md       Feilsøkingsrapport fra 27. mai 2026
│
└── dist/                      ← Distribusjonspakker (se dist/README.md)
    ├── zips/                          Klare zip-er for sluttbrukere
    │   ├── RENDER-Suite-v1.zip          ← ANBEFALT
    │   ├── RENDER-MulticamMarkers-v3.zip
    │   └── TeamsToCSV-v1.zip
    ├── unpacked/                      Utpakkede mapper (input for re-zipping)
    │   ├── RENDER-Suite/
    │   ├── RENDER-MulticamMarkers/
    │   └── TeamsToCSV/
    └── archive/                       Eldre versjoner
        └── RENDER-MulticamMarkers-v1.zip
```

---

## Hva er hvor?

| Vil du... | Gå til |
|---|---|
| ...lese om hvordan dette virker | [`docs/DOKUMENTASJON.md`](docs/DOKUMENTASJON.md) |
| ...se siste endringer | [`docs/CHANGELOG.md`](docs/CHANGELOG.md) |
| ...se hvilke problemer som ble løst | [`docs/PROBLEM-RAPPORT.md`](docs/PROBLEM-RAPPORT.md) |
| ...sende patch til gamle brukere | `dist/zips/RENDER-Markers-v1.24-Patch.zip` |
| ...publisere ny versjon (auto-update) | `./release.sh v1.25` |
| ...endre Premiere-pluginen | `premiere-plugin/` (HTML+JS+JSX) |
| ...endre TeamsToCSV-appen | `TeamsToCSV/main.swift` |
| ...bygge TeamsToCSV på nytt | `cd TeamsToCSV && ./build.sh` |
| ...se hva CSV skal inneholde | `examples/2026-05-27.csv` |

---

## Hurtigstart (utvikler)

### Bygge TeamsToCSV på nytt

```bash
cd TeamsToCSV
./build.sh
# → TeamsToCSV.app er nå oppdatert
```

### Endre Premiere-pluginen lokalt

```bash
# Rediger i premiere-plugin/index.html eller host.jsx
# Kopier til Premieres extension-mappe:

cp premiere-plugin/index.html  "$HOME/Library/Application Support/Adobe/CEP/extensions/com.render.teamsmc2/client/index.html"
cp premiere-plugin/host.jsx    "$HOME/Library/Application Support/Adobe/CEP/extensions/com.render.teamsmc2/host/host.jsx"

# Restart Premiere (Cmd+Q og åpne igjen)
```

### Publisere ny versjon (auto-update for alle brukere)

```bash
./release.sh v1.25                          # standard release-tekst
./release.sh v1.25 "Fikser noten-bug"       # med egen tekst
```

Scriptet bumper versjon, bygger, zipper, tagger, og publiserer GitHub Release.
Brukere som har v1.14+ får banner ved neste appstart. Krever `gh auth login`
én gang. Se [`docs/DOKUMENTASJON.md` §6.1b](docs/DOKUMENTASJON.md).

---

## Distribusjon (sluttbruker)

**For nye brukere ELLER brukere med v1.11 eller eldre (Patch11):**
Send `dist/zips/RENDER-Markers-v1.24-Patch.zip` (Developer ID-signert +
notarisert). De pakker ut og dobbeltklikker `RENDER Markers Oppdaterer`.

**For brukere med v1.14 eller nyere:** De får automatisk banner i appen ved
neste oppstart når du har kjørt `./release.sh v1.25`. Ingen manuell handling
kreves fra deg utover å publisere release-en.

Se [`docs/DOKUMENTASJON.md`](docs/DOKUMENTASJON.md) for full beskrivelse.

---

## Kontakt

© ENSAMBLE AS · victoria@ensamble.no
