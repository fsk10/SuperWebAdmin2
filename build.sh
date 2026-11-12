#!/bin/bash
# Builds SuperWebAdmin2.u with the UCC from a local UT 469 install.
# The build runs in ./build (a private copy of the needed engine files), so the
# UT install itself is never modified.
#
#   ./build.sh            build
#   ./build.sh --setup    (re)create ./build from the UT install first
set -euo pipefail

UT_DIR="${UT_DIR:-/d/UnrealTournament_469f_RC5}"
PKG="SuperWebAdmin2"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
SYS="$BUILD/System"

setup() {
    echo "Setting up $BUILD from $UT_DIR"
    rm -rf "$BUILD"
    mkdir -p "$SYS"
    local f
    cp "$UT_DIR"/System/UCC.exe "$UT_DIR"/System/*.dll "$SYS/"
    rm -f "$SYS"/ACE*.dll "$SYS"/NPLoader*.dll
    for f in Core Engine Editor Fire IpDrv UWeb UWindow UBrowser UnrealShare UnrealI UMenu Botpack IpServer UTServerAdmin UTMenu UTBrowser; do
        cp "$UT_DIR/System/$f.u" "$SYS/"
    done
    cp "$UT_DIR"/System/*.int "$SYS/" 2>/dev/null || true
    # Botpack/UnrealShare import sounds and textures.
    mkdir -p "$BUILD/Sounds" "$BUILD/Textures"
    cp "$UT_DIR"/Sounds/*.uax "$BUILD/Sounds/"
    cp "$UT_DIR"/Textures/*.utx "$BUILD/Textures/"

    sed -e '/^EditPackages=EpicCustomModels/,/^EditPackages=udemo/d' \
        -e "/^EditPackages=UTBrowser/a EditPackages=$PKG" \
        "$UT_DIR/System/Default.ini" > "$SYS/Build.ini"
    cp "$SYS/Build.ini" "$SYS/BuildUser.ini"
}

if [ "${1:-}" = "--setup" ] || [ ! -f "$SYS/UCC.exe" ]; then setup; fi

# Fresh copy of the sources; UCC only rebuilds a package that is missing.
rm -rf "$BUILD/$PKG" "$SYS/$PKG.u"
mkdir -p "$BUILD/$PKG"
cp -r "$ROOT/src/$PKG/Classes" "$BUILD/$PKG/"

cd "$SYS"
./UCC.exe make -ini=Build.ini -userini=BuildUser.ini -silent 2>&1 | tee "$BUILD/make.log" \
    | grep -E -i "error|warning|Success|Failure|Compiling" || true

if [ ! -f "$SYS/$PKG.u" ]; then
    echo "BUILD FAILED - see build/make.log"
    exit 1
fi
mkdir -p "$ROOT/dist/System"
cp "$SYS/$PKG.u" "$ROOT/dist/System/"
echo "Built dist/System/$PKG.u"
# Web templates (installed into the server's Web dir next to the other webadmins' files)
rm -rf "$ROOT/dist/Web"
cp -r "$ROOT/Web" "$ROOT/dist/Web"
echo "Copied Web templates to dist/Web"
