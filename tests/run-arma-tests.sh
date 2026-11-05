#!/usr/bin/env bash
# Runs the AIC regression mission on a local Arma 3 dedicated server (Windows,
# Git Bash) and reports the results from the RPT.
#
#   tests/run-arma-tests.sh                      # ARMA defaults below
#   ARMA="/d/SteamLibrary/steamapps/common/Arma 3" SOAK=240 tests/run-arma-tests.sh
#
# What it touches outside the repo: <ARMA>/MPMissions/aic_regression.VR (copied
# fresh every run). The mod is staged in .hemttout/arma-test, the server
# profile and RPT live there too. Exit code 0 only when every check passed and
# the RPT holds no script error.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARMA="${ARMA:-/d/SteamLibrary/steamapps/common/Arma 3}"
SOAK="${SOAK:-240}"
TIMEOUT="${TIMEOUT:-1200}"
STAGE="$REPO/.hemttout/arma-test"
MISSION=aic_regression.VR

[ -x "$ARMA/arma3server_x64.exe" ] || { echo "no arma3server_x64.exe in $ARMA" >&2; exit 2; }

echo "== build"
(cd "$REPO" && hemtt build >/dev/null 2>&1) || { (cd "$REPO" && hemtt build); exit 2; }

echo "== stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/@aic_test" "$STAGE/profile"
cp -r "$REPO/.hemttout/build/." "$STAGE/@aic_test/"
rm -rf "$ARMA/MPMissions/$MISSION"
mkdir -p "$ARMA/MPMissions"
cp -r "$REPO/tests/missions/$MISSION" "$ARMA/MPMissions/"
# soak length for this run
printf '\nAIC_T_SOAK = %s;\n' "$SOAK" > "$ARMA/MPMissions/$MISSION/init.sqf"

cat > "$STAGE/server.cfg" <<CFG
hostname = "aic-regression";
password = "aic-local-only";
maxPlayers = 1;
persistent = 1;
autoSelectMission = true;
verifySignatures = 0;
kickDuplicate = 0;
class Missions { class Regression { template = "${MISSION%.VR}.VR"; difficulty = "Regular"; }; };
CFG

W() { cygpath -w "$1"; }
echo "== server (soak ${SOAK}s, timeout ${TIMEOUT}s)"
"$ARMA/arma3server_x64.exe" -port=2402 -name=aic -autoInit -showScriptErrors -noSound \
    "-config=$(W "$STAGE/server.cfg")" "-profiles=$(W "$STAGE/profile")" "-mod=$(W "$STAGE/@aic_test")" &
PID=$!

rpt() { ls -t "$STAGE/profile"/*.rpt 2>/dev/null | head -1; }
START=$(date +%s)
while :; do
    R="$(rpt || true)"
    if [ -n "$R" ] && grep -q "AIC_TEST|DONE" "$R"; then break; fi
    if ! kill -0 "$PID" 2>/dev/null; then echo "server exited early" >&2; break; fi
    if [ $(( $(date +%s) - START )) -gt "$TIMEOUT" ]; then echo "timed out" >&2; break; fi
    sleep 5
done
sleep 2
taskkill //F //IM arma3server_x64.exe >/dev/null 2>&1 || kill "$PID" 2>/dev/null || true

R="$(rpt || true)"
[ -n "$R" ] || { echo "no RPT written" >&2; exit 2; }
cp "$R" "$STAGE/last.rpt"
echo "== results ($STAGE/last.rpt)"
grep -a "AIC_TEST|" "$R" | sed 's/^[0-9: ]*//' | grep -av "AIC_TEST|SOAKSTAT" || true
echo "== soak stats"
grep -a "AIC_TEST|SOAKSTAT" "$R" | sed 's/^[0-9: ]*//' | cut -c1-260 || true
echo "== script errors"
ERR=$(grep -a -n -A6 "Error in expression\|Error position\|Error Undefined\|Error Generic\|Error Type\|Error Missing\|Error Zero divisor\|Error Invalid number\|Error Foreign" "$R" || true)
if [ -n "$ERR" ]; then echo "$ERR" | head -120; else echo "none"; fi

FAILS=$(grep -ac "AIC_TEST|.*|FAIL|" "$R" || true)
DONE=$(grep -ac "AIC_TEST|DONE" "$R" || true)
[ "$DONE" -ge 1 ] && [ "$FAILS" -eq 0 ] && [ -z "$ERR" ]
