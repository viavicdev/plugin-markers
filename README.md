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
| ...se hvilke problemer som ble løst | [`docs/PROBLEM-RAPPORT.md`](docs/PROBLEM-RAPPORT.md) |
| ...sende pakken til en bruker | `dist/zips/RENDER-Suite-v1.zip` |
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

### Bygge ny distribusjon

Manuell prosess (kan automatiseres senere):
1. Bygg TeamsToCSV på nytt med `./build.sh`
2. Synkroniser oppdaterte filer til `dist/unpacked/RENDER-Suite/extension/...`
3. Synkroniser oppdatert `TeamsToCSV.app` til `dist/unpacked/RENDER-Suite/`
4. `cd dist/unpacked && zip -rqy ../zips/RENDER-Suite-v2.zip RENDER-Suite -x "*.DS_Store"`

---

## Distribusjon (sluttbruker)

Send `dist/RENDER-Suite-v1.zip` til brukeren. De:
1. Pakker ut
2. Dobbeltklikker `install.command`
3. Følger instruksene i terminalen (svarer J/n på Tesseract/Homebrew)

Se [`docs/DOKUMENTASJON.md`](docs/DOKUMENTASJON.md) for full beskrivelse.

---

## Kontakt

© ENSAMBLE AS · victoria@ensamble.no
