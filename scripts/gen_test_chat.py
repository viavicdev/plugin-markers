#!/usr/bin/env python3
"""Genererer en test-PNG som ligner en Teams-chat for å teste TeamsToCSV's parser.
Inkluderer alle edge-cases vi har fikset."""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

OUT = Path.home() / "Desktop" / "test-teams-chat.png"

# Teams dark bg
BG = (35, 36, 40)
BUBBLE_BG = (51, 53, 60)
NAME_COLOR = (180, 180, 200)
TIME_COLOR = (160, 160, 180)
BODY_COLOR = (235, 235, 240)

# Font - try common system fonts
FONT_BODY = None
FONT_NAME = None
for path in ["/System/Library/Fonts/Helvetica.ttc",
             "/System/Library/Fonts/Supplemental/Arial.ttf",
             "/System/Library/Fonts/Helvetica.dfont"]:
    try:
        FONT_BODY = ImageFont.truetype(path, 14)
        FONT_NAME = ImageFont.truetype(path, 13)
        break
    except Exception:
        continue
if not FONT_BODY:
    FONT_BODY = ImageFont.load_default()
    FONT_NAME = ImageFont.load_default()

# Test-meldinger med alle edge-cases vi har fikset.
# (sender, timestamp, body)
MESSAGES = [
    ("Håkon Blakstad", "09:15",
     "KRISTIAN og DAG OTTO ankommer hotellet. Prat på utsiden. "
     "Førsteinntrykk. Bra vibe."),

    # Edge-case 1: melding med standalone proper nouns midt i ("Paolo.", "Daniel.")
    # Skal IKKE kuttes ved navnene
    ("Håkon Blakstad", "10:30",
     "GIANLUCA forklarer bemanningen i resepsjon. Chiara som gjør alt, "
     "men er på ferie også. Paolo. Daniel. Morgenskift, ettermiddag og "
     "natt. Normalt 4 personer. Pluss tilkalling. Credit card machine. "
     "Tax machine. Betaling."),

    # Edge-case 2: tidsintervall i starten av meldingen
    # Skal plassere marker på 11:00, behold resten som kommentar
    ("Håkon Blakstad", "11:00",
     "11:00-11:30 lunsj-segment i kjøkkenet. Gianluca viser hvordan de "
     "lager frokost. Halvstekte croissanter."),

    # Edge-case 3: lang melding som spenner over mange visuelle linjer
    # Skal akkumuleres som én komplett kommentar
    ("Håkon Blakstad", "12:45",
     "Resepsjonsbordet. De går gjennom rutiner for innsjekk. Hvordan "
     "håndtere klager. Nattevaktrutiner. Drive maskin. Skru av musikk. "
     "Goerasken. Forklarer at nattevakten kan sove til ca 06, så må "
     "stå opp og begynne å forberede frokost."),

    # Edge-case 4: kort melding som slutter midt i setning (ingen . eller !)
    # Skal få ⚠ truncation-varsel
    ("Håkon Blakstad", "14:15",
     "Kristian sier dette er stort dette er en stor"),

    # Edge-case 5: enda en melding fra samme sender (for å trigge sender-stripping)
    ("Håkon Blakstad", "15:30",
     "Avslutning av dag 1. Alle er imponert over Gianluca. Dag Otto er "
     "sliten. Kristian gira. Begge er enige om at dette kommer til å bli "
     "krevende."),

    # Edge-case 6: nok en — for å sikre sender-detektor får nok data
    ("Håkon Blakstad", "16:00",
     "Møte med Elisabetta. Forklarer fagskolen. Tar dem rundt i bygget. "
     "Snakker om kurset i hotelldrift."),
]

# Layout
WIDTH = 780
MARGIN_X = 24
BUBBLE_PAD = 14
SPACING = 16

# Wrapper for text wrapping at given width
def wrap_text(text, font, max_width):
    words = text.split()
    lines = []
    current = []
    for w in words:
        test = " ".join(current + [w])
        bbox = font.getbbox(test)
        if bbox[2] - bbox[0] <= max_width:
            current.append(w)
        else:
            if current:
                lines.append(" ".join(current))
            current = [w]
    if current:
        lines.append(" ".join(current))
    return lines

# Forberegn høyde
total_height = 24
for _, _, body in MESSAGES:
    body_w = WIDTH - 2 * MARGIN_X - 2 * BUBBLE_PAD
    lines = wrap_text(body, FONT_BODY, body_w)
    bubble_h = 26 + 18 + len(lines) * 22 + BUBBLE_PAD
    total_height += bubble_h + SPACING

# Render
img = Image.new("RGB", (WIDTH, total_height + 30), BG)
draw = ImageDraw.Draw(img)

y = 18
for sender, ts, body in MESSAGES:
    bubble_w = WIDTH - 2 * MARGIN_X
    body_w = bubble_w - 2 * BUBBLE_PAD
    lines = wrap_text(body, FONT_BODY, body_w)
    bubble_h = 26 + 18 + len(lines) * 22 + BUBBLE_PAD

    # Sender + timestamp linje (over boblen, separate linjer for å matche Teams OCR)
    draw.text((MARGIN_X + 4, y), sender, font=FONT_NAME, fill=NAME_COLOR)
    name_bbox = FONT_NAME.getbbox(sender)
    name_w = name_bbox[2] - name_bbox[0]
    draw.text((MARGIN_X + 4 + name_w + 12, y), ts, font=FONT_NAME, fill=TIME_COLOR)
    y += 22

    # Bubble
    draw.rounded_rectangle(
        (MARGIN_X, y, MARGIN_X + bubble_w, y + bubble_h - 22),
        radius=8, fill=BUBBLE_BG
    )
    # Body
    ty = y + BUBBLE_PAD - 4
    for line in lines:
        draw.text((MARGIN_X + BUBBLE_PAD, ty), line, font=FONT_BODY, fill=BODY_COLOR)
        ty += 22

    y += bubble_h + SPACING - 22

img.save(OUT, "PNG")
print(f"✓ Skrevet: {OUT}")
print(f"  Størrelse: {img.size[0]}x{img.size[1]}px")
print(f"  Meldinger: {len(MESSAGES)}")
