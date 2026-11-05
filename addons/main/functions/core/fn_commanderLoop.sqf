/*
    Function: AIC_fnc_commanderLoop

    Description:
        Main scheduled loop of a commander. While the commander is
        "enabled" it runs AIC_fnc_commanderCycle and then waits for the
        remaining part of "loopInterval" (read every iteration so changes
        apply live). Must be spawned.

        The wait ends early when a replan has been requested
        (AIC_fnc_requestReplan, commander key "replanRequested", e.g. a
        group met the enemy) and at least "replanMinInterval" seconds have
        passed since the last cycle ended, so a fight is answered within
        seconds without the cycle ever running back to back. The request
        is cleared at the start of every cycle. The wait checks every
        AIC_REPLAN_POLL s and also ends when the commander is disabled.

    Parameters:
        0: HASHMAP - commander

    Returns:
        Nothing

    Example:
        private _h = [_cmd] spawn AIC_fnc_commanderLoop;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {};
if (count _cmd == 0) exitWith {};

private _side = _cmd getOrDefault ["side", sideUnknown];

// let the mission finish initialising before the first think step
waitUntil { time > 0 };
sleep 1;

["Commander loop started for %1", [_side]] call AIC_fnc_log;

private _cycle = 0;
private _earlyReason = "";
while { _cmd getOrDefault ["enabled", false] } do {
    private _start = diag_tickTime;
    private _startTime = time;

    // cleared before the cycle reads the battlefield: a group that meets the
    // enemy while this cycle runs asks for the next one
    _cmd set ["replanRequested", false];
    _cmd set ["replanReason", ""];

    [_cmd] call AIC_fnc_commanderCycle;
    _cycle = _cycle + 1;
    private _cycleEnd = time;

    private _elapsed = diag_tickTime - _start;
    if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
        private _why = ["", format [" (early: %1)", _earlyReason]] select (_earlyReason != "");
        ["%1 cycle %2 took %3 ms%4", [_side, _cycle, round (_elapsed * 1000), _why]] call AIC_fnc_log;
    };

    private _interval = ([_cmd, "loopInterval"] call AIC_fnc_getSetting) max 5;
    // the schedule is game time: subtract the cycle's game-time length (wall
    // time is only for the log; it differs under setTimeMultiplier)
    // (at least 5 s between cycles, also after one that ran over the interval)
    private _nextCycle = _cycleEnd + ((_interval - (_cycleEnd - _startTime)) max 5);

    waitUntil {
        sleep AIC_REPLAN_POLL;
        !(_cmd getOrDefault ["enabled", false])
        || { time >= _nextCycle }
        || {
            (_cmd getOrDefault ["replanRequested", false]) isEqualTo true
            && { time >= _cycleEnd + (([_cmd, "replanMinInterval"] call AIC_fnc_getSetting) max 5) }
        }
    };

    _earlyReason = "";
    if (time < _nextCycle && { (_cmd getOrDefault ["replanRequested", false]) isEqualTo true }) then {
        _earlyReason = _cmd getOrDefault ["replanReason", ""];
        if (_earlyReason isEqualTo "") then { _earlyReason = "requested"; };
    };
};

["Commander loop stopped for %1", [_side]] call AIC_fnc_log;
