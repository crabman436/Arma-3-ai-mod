#!/usr/bin/env bash
# Runs the AIC test missions on a local Arma 3 dedicated server (Windows,
# Git Bash) and reports the results from the RPT.
#
#   tests/run-arma-tests.sh                      # both missions, ARMA default below
#   MISSIONS=aic_scenarios.Stratis SOAK=240 tests/run-arma-tests.sh
#
# Missions (tests/missions/*): aic_regression.VR (unit checks of the real
# functions + a soak with two live commanders) and aic_scenarios.Stratis
# (paradrop flight from the airfield, fortification of the airfield and a
# town). tests/missions/common/harness.sqf is copied into each.
#
# What it touches outside the repo: <ARMA>/MPMissions/<mission> (copied fresh
# every run). The mod is staged in .hemttout/arma-test, the server profile and
# RPTs live there too. Exit code 0 only when every check passed (SKIPs are
# allowed) and no RPT holds a script error.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARMA="${ARMA:-/d/SteamLibrary/steamapps/common/Arma 3}"
SOAK="${SOAK:-240}"
TIMEOUT="${TIMEOUT:-1500}"
MISSIONS="${MISSIONS:-aic_regression.VR aic_scenarios.Stratis}"
STAGE="$REPO/.hemttout/arma-test"

[ -x "$ARMA/arma3server_x64.exe" ] || { echo "no arma3server_x64.exe in $ARMA" >&2; exit 2; }
if tasklist 2>/dev/null | grep -qi "arma3server_x64.exe"; then
    echo "an Arma 3 dedicated server is already running; stop it first" >&2; exit 2
fi

echo "== build"
(cd "$REPO" && hemtt build >/dev/null 2>&1) || { (cd "$REPO" && hemtt build); exit 2; }

echo "== stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/@aic_test"
cp -r "$REPO/.hemttout/build/." "$STAGE/@aic_test/"
W() { cygpath -w "$1"; }

STATUS=0
for MISSION in $MISSIONS; do
    echo
    echo "######## $MISSION"
    PROFILE="$STAGE/profile-$MISSION"
    mkdir -p "$PROFILE" "$ARMA/MPMissions"
    rm -rf "$ARMA/MPMissions/$MISSION"
    cp -r "$REPO/tests/missions/$MISSION" "$ARMA/MPMissions/"
    cp "$REPO/tests/missions/common/"*.sqf "$ARMA/MPMissions/$MISSION/"
    # soak length for this run
    printf '\nAIC_T_SOAK = %s;\n' "$SOAK" > "$ARMA/MPMissions/$MISSION/init.sqf"
    cat > "$STAGE/server-$MISSION.cfg" <<CFG
hostname = "aic-tests";
password = "aic-local-only";
maxPlayers = 1;
persistent = 1;
autoSelectMission = true;
verifySignatures = 0;
kickDuplicate = 0;
class Missions { class Test { template = "$MISSION"; difficulty = "Regular"; }; };
CFG

    echo "== server (soak ${SOAK}s, timeout ${TIMEOUT}s)"
    "$ARMA/arma3server_x64.exe" -port=2402 -name=aic -autoInit -showScriptErrors \
        "-config=$(W "$STAGE/server-$MISSION.cfg")" "-profiles=$(W "$PROFILE")" "-mod=$(W "$STAGE/@aic_test")" >/dev/null 2>&1 &
    PID=$!

    rpt() { ls -t "$PROFILE"/*.rpt 2>/dev/null | head -1; }
    START=$(date +%s)
    while :; do
        R="$(rpt || true)"
        if [ -n "$R" ] && grep -q "AIC_TEST|DONE" "$R"; then break; fi
        if ! kill -0 "$PID" 2>/dev/null; then echo "server exited early" >&2; break; fi
        if [ $(( $(date +%s) - START )) -gt "$TIMEOUT" ]; then echo "timed out" >&2; break; fi
        sleep 5
    done
    sleep 2
    # only the server this run started
    WPID="$(cat "/proc/$PID/winpid" 2>/dev/null || true)"
    if [ -n "$WPID" ]; then taskkill //F //PID "$WPID" >/dev/null 2>&1 || true; fi
    kill "$PID" 2>/dev/null || true
    sleep 3

    R="$(rpt || true)"
    if [ -z "$R" ]; then echo "no RPT written" >&2; STATUS=2; continue; fi
    cp "$R" "$STAGE/last-$MISSION.rpt"
    echo "== results ($STAGE/last-$MISSION.rpt)"
    grep -a "AIC_TEST|" "$R" | sed 's/^[0-9: ]*//' | grep -av "AIC_TEST|SOAKSTAT\|AIC_TEST|RUN|" || true
    if grep -aq "AIC_TEST|SOAKSTAT" "$R"; then
        echo "== soak stats"
        grep -a "AIC_TEST|SOAKSTAT" "$R" | sed 's/^[0-9: ]*//' | cut -c1-260 || true
    fi
    echo "== script errors"
    ERR=$(grep -a -n -A6 "Error in expression\|Error position\|Error Undefined\|Error Generic\|Error Type\|Error Missing\|Error Zero divisor\|Error Invalid number\|Error Foreign" "$R" || true)
    if [ -n "$ERR" ]; then printf '%s
' "$ERR" | head -120 || true; STATUS=1; else echo "none"; fi
    FAILS=$(grep -ac "AIC_TEST|.*|FAIL|" "$R" || true)
    DONE=$(grep -ac "AIC_TEST|DONE" "$R" || true)
    if [ "$DONE" -lt 1 ] || [ "$FAILS" -gt 0 ]; then STATUS=1; fi
done
exit $STATUS
