/*
    Function: AIC_fnc_requestReplan

    Description:
        Asks a commander to run its next cycle early instead of waiting for
        the rest of "loopInterval". AIC_fnc_commanderLoop starts that cycle
        once "replanMinInterval" seconds have passed since the last cycle
        ended. Cheap and safe in event handlers: it only sets the commander
        keys "replanRequested" and "replanReason" (the reason is only for
        the debug log; the first reason since the last cycle is kept). The
        loop clears both at the start of every cycle, so a request made
        while a cycle runs asks for the next one.

        Called by AIC_fnc_groupEngaged when a group meets the enemy or is
        shot down to its retreat threshold (setting "replanOnContact").
        Mission scripts may call it too, whatever that setting says.
        Server only.

    Parameters:
        0: HASHMAP - commander
        1: STRING  - (optional) reason, shown in the debug log

    Returns:
        BOOL - true if a request is now pending

    Example:
        [[east] call AIC_fnc_getCommander, "alarm at the airfield"] call AIC_fnc_requestReplan;
*/

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_reason", "", [""]]
];

if (!isServer) exitWith { false };
if (count _cmd == 0) exitWith { false };
if !(_cmd getOrDefault ["enabled", false]) exitWith { false };

if ((_cmd getOrDefault ["replanRequested", false]) isEqualTo true) exitWith { true };

_cmd set ["replanRequested", true];
_cmd set ["replanReason", _reason];

true
