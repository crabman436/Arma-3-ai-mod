#!/usr/bin/env bash
# Runs the AIC test missions on a local Arma 3 dedicated server (Windows,
# Git Bash) and reports the results from the RPT.
#
#   tests/run-arma-tests.sh                      # both missions, ARMA default below
#   MISSIONS=aic_scenarios.Stratis SOAK=240 tests/run-arma-tests.sh
#   MISSIONS=aic_stress.Altis SOAK=600 GROUPS_PER_SIDE=80 tests/run-arma-tests.sh   (load test)
#   HC=2 MISSIONS=aic_stress.Altis tests/run-arma-tests.sh   (with 2 headless clients)
#   ONLY=t_hc HC=1 MISSIONS=aic_regression.VR tests/run-arma-tests.sh   (only matching test files)
#   MODS="@CBA_A3;@ace" ONLY=t_fastrope MISSIONS=aic_scenarios.Stratis tests/run-arma-tests.sh
#       (other mods loaded as well: folder names under <ARMA>/!Workshop or <ARMA>, ";"-separated)
#
# Missions (tests/missions/*): aic_regression.VR (unit checks of the real
# functions + a soak with two live commanders) and aic_scenarios.Stratis
# (paradrop flight from the airfield, fortification of the airfield and a
# town). tests/missions/common/harness.sqf is copied into each.
#
# What it touches outside the repo: <ARMA>/MPMissions/<mission> (copied fresh
# every run). The mod is staged in .hemttout/arma-test, the server profile and
# RPTs live there too. HC=N (default 0) also starts N headless clients on
# this PC (each mission has three slots; their RPTs are checked too). Exit
# code 0 only when every check passed (SKIPs are allowed) and no RPT holds a
# script error.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARMA="${ARMA:-/d/SteamLibrary/steamapps/common/Arma 3}"
SOAK="${SOAK:-240}"
TIMEOUT="${TIMEOUT:-1500}"
MISSIONS="${MISSIONS:-aic_regression.VR aic_scenarios.Stratis}"
HC="${HC:-0}"
STAGE="$REPO/.hemttout/arma-test"
# extra mods, by folder name (<ARMA>/!Workshop/<name> or <ARMA>/<name>)
MODLIST=""
IFS=';' read -ra _MODS <<< "${MODS:-}"
for M in "${_MODS[@]}"; do
    [ -z "$M" ] && continue
    if [ -d "$ARMA/!Workshop/$M" ]; then MODLIST="$MODLIST;$(cygpath -w "$ARMA/!Workshop/$M")"
    elif [ -d "$ARMA/$M" ]; then MODLIST="$MODLIST;$(cygpath -w "$ARMA/$M")"
    else echo "mod $M not found under $ARMA" >&2; exit 2; fi
done

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
    # soak length and (stress mission) groups per side for this run
    printf '\nAIC_T_SOAK = %s;\nAIC_T_GROUPS = %s;\nAIC_T_HC = %s;\nAIC_T_ONLY = "%s";\n' "$SOAK" "${GROUPS_PER_SIDE:-80}" "$HC" "${ONLY:-}" > "$ARMA/MPMissions/$MISSION/init.sqf"
    cat > "$STAGE/server-$MISSION.cfg" <<CFG
hostname = "aic-tests";
password = "aic-local-only";
maxPlayers = 4;
persistent = 1;
autoSelectMission = true;
verifySignatures = 0;
kickDuplicate = 0;
headlessClients[] = {"127.0.0.1"};
localClient[] = {"127.0.0.1"};
class Missions { class Test { template = "$MISSION"; difficulty = "Regular"; }; };
CFG

    echo "== server (soak ${SOAK}s, timeout ${TIMEOUT}s)"
    "$ARMA/arma3server_x64.exe" -port=2402 -name=aic -autoInit -showScriptErrors \
        "-config=$(W "$STAGE/server-$MISSION.cfg")" "-profiles=$(W "$PROFILE")" "-mod=$(W "$STAGE/@aic_test")$MODLIST" >/dev/null 2>&1 &
    PID=$!
    # headless clients, once the server has loaded the mission
    HPIDS=""
    if [ "$HC" -gt 0 ]; then
        sleep 20
        for i in $(seq 1 "$HC"); do
            mkdir -p "$PROFILE-hc$i"
            # one at a time, each until it is in the mission (its loop logs
            # "hcLoop:"): a client that connects while another still loads
            # the map gives up; such a client gets one more try
            for TRY in 1 2; do
                rm -f "$PROFILE-hc$i"/*.rpt
                "$ARMA/arma3server_x64.exe" -client -connect=127.0.0.1 -port=2402 -password=aic-local-only "-name=hc$i" \
                    "-profiles=$(W "$PROFILE-hc$i")" "-mod=$(W "$STAGE/@aic_test")$MODLIST" >/dev/null 2>&1 &
                HP=$!
                HPIDS="$HPIDS $HP"
                HSTATE=""
                for n in $(seq 1 60); do
                    sleep 3
                    H="$(ls -t "$PROFILE-hc$i"/*.rpt 2>/dev/null | head -1 || true)"
                    if [ -n "$H" ] && grep -aq "hcLoop:" "$H"; then HSTATE=in; break; fi
                    if [ -n "$H" ] && grep -aq "giving up" "$H"; then HSTATE=gaveup; break; fi
                    if ! kill -0 "$HP" 2>/dev/null; then HSTATE=gone; break; fi
                done
                echo "== headless client $i (try $TRY): ${HSTATE:-timed out}"
                if [ "$HSTATE" = in ]; then break; fi
                WP="$(cat "/proc/$HP/winpid" 2>/dev/null || true)"
                if [ -n "$WP" ]; then taskkill //F //PID "$WP" >/dev/null 2>&1 || true; fi
            done
        done
    fi

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
    for P in $HPIDS $PID; do
        WPID="$(cat "/proc/$P/winpid" 2>/dev/null || true)"
        if [ -n "$WPID" ]; then taskkill //F //PID "$WPID" >/dev/null 2>&1 || true; fi
        kill "$P" 2>/dev/null || true
    done
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
    RPTS="$R"
    for i in $(seq 1 "$HC"); do
        H="$(ls -t "$PROFILE-hc$i"/*.rpt 2>/dev/null | head -1 || true)"
        if [ -n "$H" ]; then cp "$H" "$STAGE/last-$MISSION-hc$i.rpt"; RPTS="$RPTS $H"; else echo "headless client $i wrote no RPT"; fi
    done
    ERR=$(for F in $RPTS; do grep -a -n -A6 "Error in expression\|Error position\|Error Undefined\|Error Generic\|Error Type\|Error Missing\|Error Zero divisor\|Error Invalid number\|Error Foreign" "$F" | sed "s|^|$(basename "$F"): |" || true; done)
    if [ -n "$ERR" ]; then printf '%s
' "$ERR" | head -120 || true; STATUS=1; else echo "none"; fi
    FAILS=$(grep -ac "AIC_TEST|.*|FAIL|" "$R" || true)
    DONE=$(grep -ac "AIC_TEST|DONE" "$R" || true)
    if [ "$DONE" -lt 1 ] || [ "$FAILS" -gt 0 ]; then STATUS=1; fi
done
exit $STATUS
