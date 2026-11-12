#!/bin/bash
# Builds SWATestMuts.u: 120 trivial mutators listed in SWATestMuts.int (to push the
# mutator count far past the old limit of 50) plus NoIntMut, which has no .int entry.
# Needs ./build.sh to have set up ./build. Output: testserver/System (if it exists) and build/.
#
#   tests/build_test_mutators.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYS="$ROOT/build/System"
PKG=SWATestMuts
N=120

[ -f "$SYS/UCC.exe" ] || { echo "Run ./build.sh first"; exit 1; }

rm -rf "$ROOT/build/$PKG" "$SYS/$PKG.u"
mkdir -p "$ROOT/build/$PKG/Classes"
INT="$ROOT/build/$PKG.int"
printf '[Public]\r\n' > "$INT"
for i in $(seq -w 1 $N); do
    printf 'class TestMut%s expands Mutator;\r\n' "$i" > "$ROOT/build/$PKG/Classes/TestMut$i.uc"
    printf 'Object=(Name=%s.TestMut%s,Class=Class,MetaClass=Engine.Mutator,Description="ZZ Test Mutator %s,SWA2 test")\r\n' "$PKG" "$i" "$i" >> "$INT"
done
printf 'class NoIntMut expands Mutator;\r\n' > "$ROOT/build/$PKG/Classes/NoIntMut.uc"

grep -q "^EditPackages=$PKG" "$SYS/Build.ini" || sed -i "/^EditPackages=SuperWebAdmin2/i EditPackages=$PKG" "$SYS/Build.ini"
cd "$SYS"
./UCC.exe make -ini=Build.ini -userini=BuildUser.ini -silent 2>&1 | grep -E -i "error|Success|Failure" || true
# Keep the main build independent of the test package.
sed -i "/^EditPackages=$PKG/d" "$SYS/Build.ini"
[ -f "$SYS/$PKG.u" ] || { echo "BUILD FAILED"; exit 1; }
if [ -d "$ROOT/testserver/System" ]; then
    cp "$SYS/$PKG.u" "$INT" "$ROOT/testserver/System/"
    echo "Copied $PKG into testserver/System"
fi
