# CHANGELOG — RENDER Suite

Nyeste versjoner øverst. Kronologisk logg av endringer.

---

## v1.24 — 2026-05-29

**Status:** Første offisielle GitHub Release.

### Endringer

- **Dato-kolonne fjernet fra CSV-eksport.** Vises fortsatt i app-tabellen for
  visuell verifikasjon, men eksporteres ikke (per ønske fra produsent).

### Distribusjon

- **Først release på GitHub Releases:** `https://github.com/viavicdev/plugin-markers/releases/tag/v1.24`
- **Auto-update er nå live.** Brukere med v1.14+ får banner ved oppstart.
- **Patch-zip for siste manuelle installasjon:** `dist/zips/RENDER-Markers-v1.24-Patch.zip`
  (953 KB, Developer ID-signert + notarisert + stapled).

---

## v1.20–v1.23 — 2026-05-28 (kveld)

**Stort designsesjon.** Full omdesign av TeamsToCSV basert på GLM-5-referanse.

### Visuell omarbeiding (v1.23)

- **Lyst, kjølig canvas** (`#F8F9FC` → `#EEF1F6` linear gradient + subtil rød
  radial øverst-venstre og indigo nederst-høyre).
- **Sticky header** med "Teams**To**Markers"-tittel (rødt "To"-element),
  BETA-pill, versjon, Settings text-button og info icon-button.
- **Glass-kort** for hver fil med 44×44 thumbnail-boks, filnavn + meta
  (`8 markers · 1 kanskje kuttet`), action-row og footer.
- **3-kolonners tabell:** `DATE | TIMECODE | MESSAGE` med inline gul Note-box
  under message og rød "kanskje kuttet"-pill ved siden av tekst.
- **Drop zone:** stor versjon (72px sirkulær glass-ikon-container, format-tags
  PNG/JPG/JPEG) når tomt, compact når filer er lastet.
- **Settings-sheet:** radio-cards med tittel + beskrivelse, custom
  capsule-toggle, footer-style cards for save location.
- **Info-sheet:** logo + versjon, grønne privacy-ikoner med tittel +
  beskrivelse.
- **Film-strip loader** (kort prøvd i v1.23, byttet tilbake til original
  timeline-bw.html-animasjon etter brukerønske).
- **"trunkert" → "kanskje kuttet"** (mer naturlig norsk).

### Funksjonelle tillegg

- **Auto-update-infrastruktur** (`UpdateChecker`) som sjekker
  `api.github.com/repos/viavicdev/plugin-markers/releases/latest` ved oppstart.
  Viser rødt banner hvis ny versjon er tilgjengelig, laster ned + swapper
  appen + restarter.
- **`release.sh`-script** på prosjekt-rot: bumper versjon, bygger, zipper,
  tagger, pusher, og publiserer GitHub Release med ett kall.
- **Updater-app:** fikk app-ikon (samme som TeamsToCSV) og bumpet
  `patchLabel` til matchende versjon.

### Signering

- **Developer ID-signering + Apple-notarisering** gjenopprettet for både
  Updater og innebygd TeamsToCSV. Hardened runtime aktivert, billett
  stapled. Brukere får ikke lenger Gatekeeper-popup.

---

## v1.17 — 2026-05-28 (ettermiddag)

### Nye funksjoner

- **PNG-thumbnail** (38×38) i fil-raden, generert via
  `CGImageSourceCreateThumbnailAtIndex` (retina-skarpt).
- **Quick Look på filnavn-klikk:** liten øye-ikon hinter til at filnavnet er
  klikkbart. Bruker `qlmanage -p` til å åpne Quick Look-panelet.
- **Duplikat-deteksjon via SHA256:** hash av PNG-fila sammenlignes mot
  allerede lastede filer. Hopper over duplikatet med varsel.
- **"Slå sammen alle til én CSV":** ny rød knapp i header som dukker opp
  når 2+ filer er lastet. Slår sammen alle rader, sorterer på dato +
  timecode, lar deg lagre som én CSV.

---

## v1.15–v1.16 — 2026-05-28 (ettermiddag)

### Date-kolonne lagt til

- **DATE-kolonne** (smal, 55 px) lagt til lengst til venstre i tabellen
  og i CSV-eksporten (sistnevnte ble fjernet igjen i v1.24).
- **Dato-parser:** leser Teams' dato-separator-linjer (`15. mai`, `16/5`,
  `15. mai 2024`) OG dato-prefiks på meldinger (`21:18, 15/5. body…`).
  Propagerer dato nedover til alle påfølgende rader.
- **Format normalisert til `DD/M`** for kompakt visning.
- **Fix v1.16:** tillot ledende komma/punktum så datoer i format
  `HH:MM, DD/M.` ble fanget (problem oppdaget av produsent som så at
  dato ikke endret seg ved dag-skifte).

---

## v1.12–v1.14 — 2026-05-28 (formiddag)

### Forberedelse til auto-update

- **`UpdateChecker`-klasse** lagt til i `main.swift`. Sjekker GitHub
  Releases API ved oppstart, viser banner og kan laste ned + installere
  ny versjon ved klikk.
- **Versjons-label** i header (BetaBadge med versjonsnummer i mono-font).
- **App-ikon redesign:** gikk fra gradient-glass-look til solid svart
  squircle med hvit gear-ikon (avledet fra `update.svg`). Bygd via
  `generate_icon.py` med Pillow.

---

## v1.11 — 2026-05-27 (Patch 11)

Forrige milepæl — sist offisiell distribusjon før denne sesjonen.
Sendt ut som `RENDER-Markers-Patch11.zip`. Dette er versjonen som
de aller fleste brukerne har installert akkurat nå.

Etterpå må de oppgradere én gang til v1.24 (via patch-zippen), og
fra og med v1.24 vil oppdateringer komme automatisk via GitHub.
