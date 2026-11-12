#!/bin/bash
# Starts the (ranked profile) test server with the production mutators plus test
# mutator #100 (beyond the old limit of 50), NoIntMut (no .int entry) and two extra
# URL options. Needs ./setup-testserver.sh --ranked and tests/build_test_mutators.sh.
# Loopback only (multihome). Log: console output.
cd "$(dirname "$0")/../testserver/System" || exit 1
IGP=InstaGibPlus_next-netcode-ef237853
exec ./UCC.exe server "CTF-Terra-LE102?game=NewCTF_v19.NewCTF?mutator=$IGP.UTpure,$IGP.ST_Mutator,UTCmds6.UTCmds,Botpack.NoRedeemer,SWATestMuts.TestMut100,SWATestMuts.NoIntMut?IGPlusSettings=ServerSettingsCTF?Tickrate=128" \
    ini=SWATest.ini userini=SWATestUser.ini log=../Logs/SWATest.log multihome=127.0.0.1
