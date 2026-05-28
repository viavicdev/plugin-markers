# RENDER Suite — Bruksanvisning

**Versjon:** 1.0 BETA
**© ENSAMBLE AS** · victoria@ensamble.no

---

## ⚠ Les dette FØRST

- Dette verktøyet er **spesifikt bygget for deres workflow** (multicam-redigering av reality/dokumentar fra Teams-loggede markers). Det er **ikke** et generelt OCR-verktøy og er ikke testet med andre Teams-formater eller screenshot-typer enn de jeg så hos dere i dag.
- Verktøyet er **bygget på én dag** — det kan oppstå feil. Hvis noe ikke virker, **kontakt Victoria** før du bruker tid på workarounds.
- Pluginen er **BETA**. Hvis markers havner feil, klikk "Fjern eksisterende"-knappen og prøv på nytt.
- Det er **kun testet på macOS Apple Silicon** (M1/M2/M3/M4) med Premiere Pro 2024+.

---

## Hva er dette?

To verktøy som jobber sammen:

| Verktøy | Hva |
|---|---|
| **TeamsToCSV** | Mac-app som tar Teams-screenshots → lager .csv med timecodes og kommentarer |
| **Multicam Markers** | Premiere-plugin som tar .csv-filen og skriver markers direkte på et multicam-klipp |

---

## Den ABSOLUTT VIKTIGSTE regelen

For at markers skal lande på riktig sted i multicam-klippet:

> **Multicam-klippets source-timecode må matche klokkeslettet i Teams-loggen.**

**Konvensjon vi anbefaler:** sett alltid multicam-klippets start-TC til `09:00:00:00`, uansett hvor i verden dere filmer eller når på dagen filmingen faktisk begynner. Klippet kan godt være tomt før første opptak.

Da matcher det pluginens default-verdi (`09:00:00:00`), og dere slipper å fylle inn TC-feltet manuelt hver gang. Klokkeslettene i Teams-loggen tolkes som "timer siden multicam-start" — så marker `12:30:00:00` i CSV-en lander 3 timer og 30 minutter inn i multicam-klippet.

---

## Workflow

```
1. Sync alt dagens materiale til ÉN full timeline per dag
   (deres eksisterende workflow — bilde/lyd matchet til klokkeslett)
   ↓
2. Lag multicam-klipp av timeline-en. Sett start-TC = 09:00:00:00.
   (klippet kan være tomt før første opptak)
   ↓
3. Underveis i produksjonen: noter klokkeslett + kommentarer i Teams-chat
   (én chat per dag — ikke bland flere dager i samme tråd)
   ↓
4. Ta scrolling screenshot av dagens Teams-chat med Shottr
   ↓
5. Dra screenshot inn i TeamsToCSV → få .csv
   ↓
6. I Premiere: åpne RENDER Multicam Markers-pluginen
   ↓
7. Last opp .csv → velg multicam-klipp → klikk "Skriv markers"
   ↓
8. Markers dukker opp på multicam-klippet på riktig klokkeslett ✓
```

---

## STEG 1: Lag multicam-klippet riktig

I Premiere — etter at dere har synket dagens materiale til én timeline (deres eksisterende workflow):

1. **Lag multicam-source-sequence** som dekker hele dagens timeline. Ikke kutt vekk pauser eller "tomme" deler. Markers må kunne lande hvor som helst i denne tidsperioden.
2. **Sett source-TC til `09:00:00:00`** (vår anbefalte konvensjon):
   - Høyreklikk multicam-klippet i Project-panelet
   - Velg **Modify → Timecode...**
   - I "Source Timecode": skriv `09:00:00:00`
   - Klikk OK

Klippet kan godt være tomt i starten — det er bare en tom "ramme" som lar oss bruke klokkeslett som intern tid.

**Hvorfor `09:00:00:00`?** Det matcher default-verdien i pluginen, så dere slipper å endre Start-TC-feltet manuelt hver gang. Marker `12:30:00:00` i Teams-loggen lander dermed 3 timer og 30 minutter inn i multicam-klippet — som tilsvarer "kl 12:30" hvis vi tolker `09:00:00:00` som "kl 09:00".

---

## STEG 2: Screenshot Teams-chatten med Shottr

**Bruk [Shottr](https://shottr.cc) — en gratis screenshot-app for Mac som lar deg ta lange/scrollende screenshots.**

1. Åpne Teams-chatten med dagens markers
2. Bruk Shottr sin **Scrolling Capture** for å ta hele chatten i ett bilde
3. Lagre som PNG (gjerne med dato i filnavnet: `2026-05-27_teams.png`)

**VIKTIG:**
- **Én chat = én dag = én screenshot.** Ikke screenshot to dager i samme PNG.
- Sørg for at klokkeslettene vises tydelig i screenshotet.
- Unngå å klippe vekk halve meldinger — OCR fungerer best på komplett tekst.

---

## STEG 3: Konverter screenshot til CSV

1. Åpne **TeamsToCSV.app** (i Programmer-mappen)
2. Dra PNG-en inn i drop-feltet
3. Vent på OCR-en (5-15 sekunder)
4. Sjekk forhåndsvisningen i tabellen — er noen kommentarer feil?
5. Klikk **"Rediger"** for å fikse OCR-feil direkte i tabellen
6. Klikk **"Last ned CSV"** for å lagre (default: ved siden av PNG-en)

**Endre OCR-motor i innstillinger** (⚙ øverst til høyre):
- **Tesseract (norsk)** — anbefalt, bedre på æ/ø/å
- **Apple Vision** — fallback hvis Tesseract feiler

---

## STEG 4: Skriv markers i Premiere

1. Åpne Premiere-prosjektet med multicam-klippet
2. **Window → Extensions → RENDER – Multicam Markers**
3. **Steg 1 (CSV):** Dra inn .csv-filen fra TeamsToCSV
4. **Steg 2 (KLIPP):** Velg multicam-klippet (bruk søkefeltet hvis du har mange klipp)
5. **Steg 3 (SEND):**
   - **Start-TC**: default `09:00:00:00` — la stå hvis dere fulgte konvensjonen i Steg 1
   - **FPS**: framerate på klippet (typisk `25` eller `50`)
   - Klikk **"Skriv markers"**
6. Markers dukker opp på multicam-klippet på riktige klokkeslett ✓

**Hvis noe går galt:** klikk **"🗑 Fjern eksisterende"** for å slette alle markers og prøv på nytt.

---

## Tekniske krav

| | |
|---|---|
| **macOS** | 14 (Sonoma) eller nyere |
| **Mac** | Apple Silicon (M1/M2/M3/M4) — IKKE Intel |
| **Premiere Pro** | 2024 eller nyere (testet på 26.2.2) |
| **Tesseract** | Anbefalt — installeres automatisk av installer-en |
| **Internett** | Kun for første installasjon av Homebrew/Tesseract. Ellers full offline. |

---

## Personvern

- **Alt kjøres lokalt på din maskin.**
- Ingen bilder eller data sendes til skyen, eksterne tjenester eller AI-modeller.
- Ingen telemetri, ingen tracking.
- Source-PNGer åpnes kun for lesing — aldri modifisert.

---

## CSV-format (hvis du vil lage CSV-er manuelt)

```
HH:MM:SS:FF,Kommentar
09:15:00:00,Sending starter
09:23:45:00,Reklame
```

Også støttet:

| Format | Eksempel | Forklaring |
|---|---|---|
| `HH:MM:SS:FF` | `09:15:30:12` | Time : minutt : sekund : frame |
| `HH:MM:SS` | `09:15:30` | Time : minutt : sekund |
| `HH:MM` | `09:15` | Time : minutt |
| `HH.MM` | `09.15` | Time . minutt (Teams-stil med punktum) |

---

## Kjente begrensninger og caveats

1. **OCR er ikke perfekt** — særlig på æ/ø/å. Bruk redigeringsmodus for å fikse feil før eksport.
2. **Pluginen forventer at multicam-klippets source-TC matcher klokkeslettet.** Hvis du ikke setter dette riktig, lander markers på feil sted.
3. **Auto-detect av FPS og Start-TC fungerer ikke for multicam-klipp** — de må fylles inn manuelt i pluginens steg 3.
4. **Race condition på første åpning av pluginen** — hvis steg 2 viser "Laster..." for lenge, klikk "↺ Oppdater". Vi har auto-retry med backoff, men på trege Mac-er kan det fortsatt trenge et manuelt trykk.
5. **Premiere 26+ mangler innebygd JSON** i ExtendScript — vi har lagt inn polyfill, men hvis du oppdager merkelige feilmeldinger i pluginens diagnose-vindu, kontakt Victoria.
6. **Verktøyet er bygget spesifikt for deres workflow.** Det er ikke testet med andre Teams-formater, andre chat-tjenester eller andre screenshot-stiler enn de jeg så hos dere i dag.
7. **Apper er signert og notarisert** av Apple — men kommer fra "Victoria Haugnes" (ikke et stort selskap), så macOS kan likevel be deg bekrefte første gangs åpning.

---

## Feilsøking

### "Pluginen vises ikke i Window → Extensions"
Restart Premiere helt (Cmd+Q, ikke bare lukke vinduet).

### "Plugin viser bare 'Laster...' på steg 2"
Klikk **↺ Oppdater**-knappen. Hvis det fortsatt feiler, sjekk at et prosjekt er åpent i Premiere.

### "Markers havner på feil sted"
Sjekk at **Start-TC** i pluginens steg 3 matcher multicam-klippets source-TC.

### "OCR plukker opp feil tekst / mangler norske tegn"
Bruk **Rediger**-knappen på tabellen for å fikse manuelt før eksport.

### "TeamsToCSV.app sier 'skadet'"
Kjør i Terminal:
```
xattr -cr "/Applications/TeamsToCSV.app"
```

### Andre problemer
Kontakt Victoria — vi løser det.

---

## Kontakt

**Victoria Haugnes** · victoria@ensamble.no

Verktøyet er bygget for dere. Hvis noe ikke fungerer som forventet, ikke kast bort tid på å gjette — bare ring/mail.

© ENSAMBLE AS, 2026
