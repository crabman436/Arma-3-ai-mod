/*
    Function: AIC_fnc_hcBalance

    Description:
        Hands commanded ground groups to the connected headless clients, so
        their AI (pathfinding, combat, driving) runs on other CPU cores. The
        commander keeps planning on the server and reaches them through
        AIC_fnc_do; the headless client reports what they see and their
        events back (AIC_fnc_hcLoop).

        A group moves when it is local to the server, of type INF, MOTOR,
        MECH or ARMOR, not "transportOnly", has no ride arranged (record
        "transport" null), its task is none of TRANSPORT, TRANSPORTED,
        SUPPORT, SUPPLY, RTB, and it has no "AIC_noHC" group variable. Air,
        artillery, statics, boats and the logistics roles stay on the server
        (few groups, long scripted sequences). It goes to the headless client
        with the fewest units (all sides counted), at most AIC_HC_MOVES groups
        per call. Groups of a headless client that disconnects return to the
        server on their own (engine) and are handed out again here.

        Setting "useHeadlessClients" (default true) turns it on. Called by
        AIC_fnc_commanderCycle right after AIC_fnc_registerGroups. Server only.

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - groups handed over by this call

    Example:
        [_cmd] call AIC_fnc_hcBalance;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer || { count _cmd == 0 }) exitWith { 0 };
if !(([_cmd, "useHeadlessClients"] call AIC_fnc_getSetting) isEqualTo true) exitWith { 0 };
private _hcs = [] call AIC_fnc_hcOwners;
if (_hcs isEqualTo []) exitWith { 0 };

private _gd = _cmd getOrDefault ["groupData", createHashMap];
private _candidates = (_cmd getOrDefault ["groups", []]) select {
    private _rec = _gd getOrDefault [hashValue _x, createHashMap];
    local _x
    && { count _rec > 0 }
    && { !(_x getVariable ["AIC_noHC", false]) }
    && { (_rec getOrDefault ["type", ""]) in ["INF", "MOTOR", "MECH", "ARMOR"] }
    && { !((_rec getOrDefault ["transportOnly", false]) isEqualTo true) }
    && { isNull (_rec getOrDefault ["transport", grpNull]) }
    && { !((_rec getOrDefault ["task", ""]) in ["TRANSPORT", "TRANSPORTED", "SUPPORT", "SUPPLY", "RTB"]) }
    && { ((units _x) findIf { isPlayer _x }) < 0 }
};
if (_candidates isEqualTo []) exitWith { 0 };

// units each headless client runs now (every side's groups)
private _load = createHashMap;
{ _load set [_x, 0]; } forEach _hcs;
{
    private _o = groupOwner _x;
    if (_o in _load) then { _load set [_o, (_load get _o) + count units _x]; };
} forEach allGroups;

private _moved = 0;
{
    if (_moved >= AIC_HC_MOVES) then { break };
    private _grp = _x;
    private _to = -1;
    private _min = 1e9;
    { if (_y < _min) then { _min = _y; _to = _x; }; } forEach _load;
    // marks the group as commanded for the headless client's loop, with the
    // record key the server knows it by (its events may arrive after the
    // engine deleted an emptied group)
    _grp setVariable ["AIC_hc", [hashValue _grp, side _grp], true];
    if (_grp setGroupOwner _to) then {
        _load set [_to, _min + count units _grp];
        _moved = _moved + 1;
    };
} forEach _candidates;

if (_moved > 0 && { !isNil "AIC_ns" } && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["hcBalance: %1 handed %2 groups to headless clients (units per client %3)", [_cmd getOrDefault ["side", sideUnknown], _moved, values _load]] call AIC_fnc_log;
};
_moved
