/*
    Function: AIC_fnc_removeCommander

    Description:
        Stops and removes the commander of a side (server only): disables
        and terminates its loop, deletes its debug markers and releases its
        groups (they keep their current waypoints and AI behaviour).

    Parameters:
        0: SIDE - side whose commander is removed

    Returns:
        BOOL - true if a commander was removed

    Example:
        [east] call AIC_fnc_removeCommander;
*/

params [["_side", sideUnknown, [sideUnknown]]];

if (!isServer) exitWith { false };
if (isNil "AIC_commanders") then { AIC_commanders = createHashMap; };

private _cmd = AIC_commanders getOrDefault [_side, createHashMap];
if (count _cmd == 0) exitWith { false };

_cmd set ["enabled", false];

private _handle = _cmd getOrDefault ["loopHandle", scriptNull];
if (!isNil "_handle" && { _handle isEqualType scriptNull } && { !isNull _handle } && { !scriptDone _handle }) then {
    terminate _handle;
};
_cmd set ["loopHandle", scriptNull];

// delete debug markers
{ deleteMarker _x; } forEach (_cmd getOrDefault ["markers", []]);
_cmd set ["markers", []];

// release groups
private _released = count (_cmd getOrDefault ["groups", []]);
_cmd set ["groups", []];
_cmd set ["groupData", createHashMap];
_cmd set ["plan", []];

AIC_commanders deleteAt _side;

["Commander for %1 removed, %2 groups released", [_side, _released]] call AIC_fnc_log;

true
