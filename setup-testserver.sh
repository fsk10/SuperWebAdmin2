#!/bin/bash
# Creates ./testserver: a local Windows UT 469 dedicated server with the packages of
# the PlayUnreal Regular server repo and the freshly built SuperWebAdmin2 in place of
# SuperWebAdmin.
#
#   ./setup-testserver.sh            (re)create ./testserver as the Regular server (VoteSys)
#   ./setup-testserver.sh --ranked   (re)create it as the Ranked server (no VoteSys)
#   ./setup-testserver.sh --update   only copy a new dist/ (SuperWebAdmin2.u + Web/)
#
# Start it with ./testserver/run.sh [map]
# Game port 7800, SWA2 on 7799 (game port - 1, like on the real servers).
# Test logins are written to testserver/credentials.env (never committed).
set -euo pipefail

UT_DIR="${UT_DIR:-/d/UnrealTournament_469f_RC5}"
PROFILE=regular
[ "${1:-}" = "--ranked" ] && PROFILE=ranked
if [ "$PROFILE" = ranked ]; then
    SERVER_REPO="${SERVER_REPO:-/c/Dev/PlayUnreal-CTF-Server-Ranked}"
else
    SERVER_REPO="${SERVER_REPO:-/c/Dev/PlayUnreal-CTF-Server-Regular}"
fi
ROOT="$(cd "$(dirname "$0")" && pwd)"
TS="$ROOT/testserver"
GAME_PORT=7800
SWA_PORT=7799

update_swa() {
    cp "$ROOT/dist/System/SuperWebAdmin2.u" "$TS/System/"
    if [ -d "$ROOT/dist/Web" ]; then
        cp -r "$ROOT/dist/Web/." "$TS/Web/"
    fi
    echo "Copied SuperWebAdmin2 into $TS"
}

if [ "${1:-}" = "--update" ]; then
    update_swa
    exit 0
fi

rm -rf "$TS"
mkdir -p "$TS/System" "$TS/Maps" "$TS/Logs"
cp -r "$SERVER_REPO/Textures" "$SERVER_REPO/Sounds" "$SERVER_REPO/Music" "$SERVER_REPO/Web" "$TS/"
for m in CTF-Terra-LE102 CTF-Anarchy-LE113 CTF-Azcanize-LE108 CTF-Face CTF-Coret; do
    cp "$SERVER_REPO/Maps/$m.unr" "$TS/Maps/" 2>/dev/null || true
done
cp "$SERVER_REPO"/System/*.u "$SERVER_REPO"/System/*.int "$SERVER_REPO"/System/*.ini "$TS/System/"
# The old SWA must not be loadable by accident.
rm -f "$TS/System/SuperWebAdmin.u" "$TS/System/SWAConfig.ini"
# Windows engine binaries from the local install.
cp "$UT_DIR"/System/UCC.exe "$UT_DIR"/System/*.dll "$TS/System/"
for f in Core Engine Editor Fire IpDrv UWeb UWindow UBrowser UnrealShare UnrealI UMenu Botpack IpServer UTServerAdmin UTMenu UTBrowser; do
    cp "$UT_DIR/System/$f.u" "$TS/System/"
done
rm -f "$TS"/System/ACE*.dll "$TS"/System/NPLoader*.dll
mkdir -p "$ROOT/dist/Web"
update_swa

# Server ini: the repo template without ACE/NPLoader/uplinks/stats and with SWA2.
sed -e 's/CHANGEME/SWATest/g' \
    -e '/^ServerPackages=NPLoader/d' -e '/^ServerPackages=.*ACE/d' -e '/^ServerPackages=IACE/d' \
    -e '/^ServerActors=NPLoader/d' -e '/^ServerActors=ACE/d' \
    -e '/^ServerActors=.*Uplink/d' -e 's/^DoUplink=True/DoUplink=False/' \
    -e '/^ServerActors=UTStatsLite/d' -e '/^ServerPackages=UTStatsLite/d' \
    -e 's/^ServerActors=SuperWebAdmin\.SWAServer/ServerActors=SuperWebAdmin2.SWAServer/' \
    -e "s/^Port=SWATest/Port=$GAME_PORT/" \
    "$SERVER_REPO/UnrealTournament.ini.EXAMPLE" > "$TS/System/SWATest.ini"
rnd() { head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
# Nobody may join by accident: random game password.
sed -i -e "s/^GamePassword=.*/GamePassword=$(rnd)/" -e "s/^AdminPassword=SWATest/AdminPassword=$(rnd)/" "$TS/System/SWATest.ini"
# Never talk to production: the Ranked repo's GameEventsPublisher posts to the c00lbot API.
sed -i -e '/^\[GameEventsPublisher.GameEventsConfig\]/,/^\[/ s/^bEnabled=.*/bEnabled=False/' \
       -e '/^\[GameEventsPublisher.GameEventsConfig\]/,/^\[/ s/^Host=.*/Host=127.0.0.1/' "$TS/System/SWATest.ini"
cp "$UT_DIR/System/User.ini" "$TS/System/SWATestUser.ini" 2>/dev/null || cp "$UT_DIR/System/DefUser.ini" "$TS/System/SWATestUser.ini"

# SWA2 config: SuperAdmin (5), PublicModerator (1) and ServerModerator (3) for privilege tests.
ADMIN_PW="$(rnd | cut -c1-16)"
MOD_PW="$(rnd | cut -c1-16)"
SMOD_PW="$(rnd | cut -c1-16)"
LONG_PW="$(rnd)$(rnd)"
LONG_PW="${LONG_PW:0:40}"
cat > "$TS/System/SWAConfig.ini" <<EOF
[SuperWebAdmin2.SWAConfig]
ListenPort=$SWA_PORT
MaxConnections=50
AdminRealm=SWA2 Test
UserList[0]=admin:$ADMIN_PW:5
UserList[1]=mod:$MOD_PW:1
UserList[2]=smod:$SMOD_PW:3
UserList[3]=longpw:$LONG_PW:5
UserList[4]=nopass::5
bOPBanEnabled=False
bTickrateInSettings=False
EOF
cat > "$TS/credentials.env" <<EOF
SWA_URL=http://127.0.0.1:$SWA_PORT
SWA_ADMIN_USER=admin
SWA_ADMIN_PASS=$ADMIN_PW
SWA_MOD_USER=mod
SWA_MOD_PASS=$MOD_PW
SWA_SMOD_USER=smod
SWA_SMOD_PASS=$SMOD_PW
SWA_LONG_USER=longpw
SWA_LONG_PASS=$LONG_PW
GAME_PORT=$GAME_PORT
EOF

GAME=$(grep '^MYGAME=' "$SERVER_REPO/utserver.init.EXAMPLE" | cut -d= -f2 | tr -d '\r')
# Production mutators minus the ones that report to external services.
MODS=$(grep '^MYMODS=' "$SERVER_REPO/utserver.init.EXAMPLE" | cut -d= -f2 | tr -d '\r' | tr ',' '\n' \
       | grep -v -i -E '^GameEventsPublisher\.' | paste -sd, -)
# multihome=127.0.0.1 binds all sockets to loopback: no master server uplinks and no
# outgoing connections (the engine re-adds default uplinks to the ini at runtime).
cat > "$TS/run.sh" <<EOF
#!/bin/bash
# Local SWA2 test server ($PROFILE), game port $GAME_PORT, webadmin $SWA_PORT, loopback only.
# Log: testserver/Logs/SWATest.log
MAP="\${1:-CTF-Terra-LE102}"
cd "\$(dirname "\$0")/System"
exec ./UCC.exe server "\$MAP?game=$GAME?mutator=$MODS" ini=SWATest.ini userini=SWATestUser.ini log=../Logs/SWATest.log multihome=127.0.0.1
EOF
chmod +x "$TS/run.sh"
echo "Test server ($PROFILE) ready in $TS - start with ./testserver/run.sh"
