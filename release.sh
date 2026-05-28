#!/bin/bash
# Publiserer en ny TeamsToCSV-versjon til GitHub Releases.
# Brukere som har v1.14 eller nyere installert vil få oppdaterings-banneret
# i appen ved neste oppstart.
#
# Bruk:
#   ./release.sh v1.24                          # standard release notes
#   ./release.sh v1.24 "Fikser noten-bug"       # med egen tekst
#
# Krav:
#   - gh auth login (én gang)
#   - git working tree må være ren (ingen ucommitted changes)

set -e

if [ -z "$1" ]; then
    echo "❌ Mangler versjons-tag. Bruk: ./release.sh v1.24 \"valgfri release-tekst\""
    exit 1
fi

VERSION="$1"
NOTES="${2:-Generell oppdatering. Sjekk endringer på commit-listen.}"

# Sørg for v-prefiks
if [[ ! "$VERSION" =~ ^v ]]; then
    VERSION="v$VERSION"
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/TeamsToCSV"
APP="$APP_DIR/TeamsToCSV.app"
MAIN="$APP_DIR/main.swift"

echo "▸ Sjekker forutsetninger…"
command -v gh >/dev/null || { echo "❌ gh CLI ikke installert. Kjør: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "❌ Ikke logget inn. Kjør: gh auth login"; exit 1; }

cd "$ROOT"
if [ -n "$(git status --porcelain)" ]; then
    echo "❌ Working tree er ikke ren. Commit eller stash endringene først:"
    git status --short
    exit 1
fi

# Sjekk at taggen ikke finnes fra før
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "❌ Tag $VERSION finnes allerede. Velg et høyere nummer."
    exit 1
fi

echo "▸ Bumper appVersionLabel i main.swift til $VERSION…"
# Erstatt linja: let appVersionLabel = "vX.Y"
if ! grep -q '^let appVersionLabel = ' "$MAIN"; then
    echo "❌ Fant ikke appVersionLabel-definisjonen i main.swift."
    exit 1
fi
# BSD sed på macOS — bruker -i ''
sed -i '' "s/^let appVersionLabel = .*/let appVersionLabel = \"$VERSION\"/" "$MAIN"

echo "▸ Bygger appen…"
"$APP_DIR/build.sh" | sed 's/^/    /'

if [ ! -d "$APP" ]; then
    echo "❌ Bygget fant ikke .app — avbryter."
    exit 1
fi

ZIP_NAME="TeamsToCSV-$VERSION.zip"
ZIP_PATH="$ROOT/$ZIP_NAME"

echo "▸ Zipper $APP → $ZIP_NAME…"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"
ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo "  Størrelse: $ZIP_SIZE"

echo "▸ Commiter versjons-bump…"
git add "$MAIN"
git commit -m "Release $VERSION"

echo "▸ Lager tag $VERSION…"
git tag -a "$VERSION" -m "$VERSION"

echo "▸ Pusher commit + tag…"
git push origin main
git push origin "$VERSION"

echo "▸ Lager GitHub Release med zip som asset…"
gh release create "$VERSION" \
    "$ZIP_PATH" \
    --title "$VERSION" \
    --notes "$NOTES"

echo ""
echo "✓ Release $VERSION er publisert."
echo "  Brukere får varsel i appen ved neste oppstart."
echo "  URL: $(gh release view "$VERSION" --json url -q .url)"

# Rydd zip lokalt (den ligger på GitHub nå)
rm -f "$ZIP_PATH"
