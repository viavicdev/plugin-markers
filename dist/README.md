# dist/ — Distribusjonspakker

Alle ferdige .zip-pakker og deres utpakkede kilder.

## Mappestruktur

```
dist/
├── zips/        ← Send disse til sluttbrukere
├── unpacked/    ← Utpakkede versjoner (input for re-zipping)
└── archive/     ← Eldre versjoner, beholdt for referanse
```

---

## zips/  — Sluttprodukt

Disse er klare til distribusjon (e-post, AirDrop, Dropbox).

| Fil | Hva | Anbefalt for |
|---|---|---|
| **`RENDER-Suite-v1.zip`** | Premiere-plugin + TeamsToCSV + smart installer | **Nye brukere — anbefalt** |
| `RENDER-MulticamMarkers-v3.zip` | Kun Premiere-plugin | Hvis bruker ikke trenger TeamsToCSV |
| `TeamsToCSV-v1.zip` | Kun TeamsToCSV-appen | Hvis plugin allerede er installert |

---

## unpacked/ — Utpakkede kilder

Mappene som ble pakket til zipene. Bruk disse hvis du:
- Vil inspisere innholdet uten å pakke ut
- Skal bygge en ny zip-versjon (`zip -rqy ny-versjon.zip RENDER-Suite -x "*.DS_Store"`)
- Tester install.command lokalt uten å pakke

```
unpacked/
├── RENDER-Suite/             ← input for RENDER-Suite-v1.zip
│   ├── install.command
│   ├── LES-MEG.txt
│   ├── FAQ.txt
│   ├── extension/com.render.teamsmc2/
│   └── TeamsToCSV.app/
├── RENDER-MulticamMarkers/   ← input for RENDER-MulticamMarkers-v3.zip
└── TeamsToCSV/               ← input for TeamsToCSV-v1.zip
```

---

## archive/ — Eldre versjoner

Beholdes for referanse og historikk. Ikke distribuer disse.

| Fil | Hvorfor arkivert |
|---|---|
| `RENDER-MulticamMarkers-v1.zip` | Manglet CSInterface.js → mock-data på andre Mac. Erstattet av v3. |

---

## Versjonshistorikk

| Versjon | Dato | Største endring |
|---|---|---|
| Suite v1 | 2026-05-27 | Første samlede pakke med plugin + app + smart installer |
| Plugin v3 | 2026-05-27 | JSON-polyfill for Premiere 26+, race-condition retry, diagnose-knapp |
| Plugin v1 | 2026-05-27 | Original distribusjon (manglet CSInterface.js) |
| TeamsToCSV v1 | 2026-05-27 | Første standalone-pakke med Tesseract auto-install |
