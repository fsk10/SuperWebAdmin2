#!/bin/bash
# Builds SuperWebAdmin2 and assembles the release in dist/ plus a zip:
#   dist/System/SuperWebAdmin2.u, dist/System/SWAConfig.ini.EXAMPLE,
#   dist/Web/* (templates, swa2.css, swa2.js, flags/, favicon.ico), README.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(grep -o 'const SWAVersion = "[^"]*"' "$ROOT/src/SuperWebAdmin2/Classes/SuperServerAdmin.uc" | cut -d'"' -f2)
[[ "$VERSION" =~ ^[0-9A-Za-z._-]+$ ]] || { echo "Invalid version '$VERSION'"; exit 1; }

"$ROOT/build.sh"
cp "$ROOT/dist-templates/SWAConfig.ini.EXAMPLE" "$ROOT/dist/System/"
cp "$ROOT/README.md" "$ROOT/dist/"

ZIP="$ROOT/SuperWebAdmin2-$VERSION.zip"
rm -f "$ZIP"
# Paths go to PowerShell as environment variables, never as part of the command text.
SWA_ZIP_SRC="$(cygpath -w "$ROOT/dist")" SWA_ZIP_DST="$(cygpath -w "$ZIP")"     powershell -NoProfile -Command 'Compress-Archive -Path (Join-Path $env:SWA_ZIP_SRC "*") -DestinationPath $env:SWA_ZIP_DST'
echo "Release: $ZIP"
