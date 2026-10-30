/*
    Function: AIC_fnc_commanderLoop

    Description:
        Main scheduled loop of a commander. While the commander is
        "enabled" it runs AIC_fnc_commanderCycle and then sleeps for the
        remaining part of "loopInterval" (read every iteration so changes
        apply live). Must be spawned.

    Parameters:
        0: HASHMAP - commander

    Returns:
        Nothing

    Example:
        private _h = [_cmd] spawn AIC_fnc_commanderLoop;
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {};
if (count _cmd == 0) exitWith {};

private _side = _cmd getOrDefault ["side", sideUnknown];

// let the mission finish initialising before the first think step
waitUntil { time > 0 };
sleep 1;

["Commander loop started for %1", [_side]] call AIC_fnc_log;

private _cycle = 0;
while { _cmd getOrDefault ["enabled", false] } do {
    private _start = diag_tickTime;

    [_cmd] call AIC_fnc_commanderCycle;
    _cycle = _cycle + 1;

    private _elapsed = diag_tickTime - _start;
    if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
        ["%1 cycle %2 took %3 ms", [_side, _cycle, round (_elapsed * 1000)]] call AIC_fnc_log;
    };

    private _interval = [_cmd, "loopInterval"] call AIC_fnc_getSetting;
    if !(_interval isEqualType 0) then { _interval = 30; };
    _interval = _interval max 5;

    sleep ((_interval - _elapsed) max 1);
};

["Commander loop stopped for %1", [_side]] call AIC_fnc_log;
