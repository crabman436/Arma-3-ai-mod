/*
    Function: AIC_fnc_dynSimCycle

    Description:
        Parks idle groups and wakes groups the commander needs (server only),
        using AIC_fnc_setGroupSim. Runs only if setting "manageDynSim" is
        true; if it was turned off, every group AIC parked is woken once.

        A group is WOKEN if any of these holds:
          - its task is ATTACK, REINFORCE, RETREAT, SUPPORT, TRANSPORT,
            TRANSPORTED or RTB;
          - a known enemy contact or threat cluster is within
            "dynSimWakeRange" of its leader;
          - (parked groups only, one nearEntities query per group and
            cycle) a hostile unit / vehicle is within "dynSimWakeRange" of
            its leader. Parked groups are blind, so this is how they notice
            an enemy coming.
        A group is PARKED if all of these hold:
          - its task is IDLE, DEFEND or PATROL;
          - it is not moving: no waypoint left, or leader within 100 m of
            "taskPos", or the task is older than 120 s;
          - it is not in COMBAT behaviour;
          - no wake condition applies.
        Everything else is left as it is.

    Parameters:
        0: HASHMAP - commander

    Returns:
        ARRAY - [number of groups parked this cycle, number woken this cycle]

    Example:
        [_cmd] call AIC_fnc_dynSimCycle;
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith { [0, 0] };
if (count _cmd == 0) exitWith { [0, 0] };

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith { [0, 0] };
private _records = (values _groupData) select { _x isEqualType createHashMap };
if (_records isEqualTo []) exitWith { [0, 0] };

// --- management turned off: release everything AIC parked, then stop
if !(([_cmd, "manageDynSim"] call AIC_fnc_getSetting) isEqualTo true) exitWith {
    private _woken = 0;
    {
        private _grp = _x getOrDefault ["group", grpNull];
        if (_x getOrDefault ["parked", false] && { _grp isEqualType grpNull } && { !isNull _grp }) then {
            if ([_cmd, _grp, false] call AIC_fnc_setGroupSim) then { _woken = _woken + 1; };
        };
    } forEach _records;
    [0, _woken]
};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _range = [_cmd, "dynSimWakeRange"] call AIC_fnc_getSetting;
if (!(_range isEqualType 0) || { _range <= 0 }) then { _range = 1000; };

private _wakeTasks = ["ATTACK", "REINFORCE", "RETREAT", "SUPPORT", "TRANSPORT", "TRANSPORTED", "RTB"];
private _parkTasks = ["IDLE", "DEFEND", "PATROL"];
private _entityTypes = ["CAManBase", "LandVehicle", "Air", "Ship"];

// --- enemy positions the commander already knows about (contacts + cluster centres)
private _enemyPositions = [];
{
    if (_x isEqualType createHashMap) then {
        private _p = _x getOrDefault ["pos", []];
        if (_p isEqualType [] && { count _p >= 2 }) then { _enemyPositions pushBack _p; };
    };
} forEach ((_cmd getOrDefault ["knownEnemies", []]) + (_cmd getOrDefault ["threats", []]));

private _parked = 0;
private _woken = 0;

{
    private _rec = _x;
    private _grp = _rec getOrDefault ["group", grpNull];
    if (!(_grp isEqualType grpNull) || { isNull _grp }) then { continue };
    if (_grp getVariable ["AIC_noDynSim", false]) then { continue };

    private _alive = (units _grp) select { alive _x };
    if (_alive isEqualTo []) then { continue };

    private _leader = leader _grp;
    if (isNull _leader || { !alive _leader }) then { _leader = _alive select 0; };
    private _lpos = getPosATL _leader;

    private _isParked = dynamicSimulationEnabled _grp;
    _rec set ["parked", _isParked];

    private _task = _rec getOrDefault ["task", "IDLE"];
    if !(_task isEqualType "") then { _task = "IDLE"; };

    // ---------------------------------------------------------- wake conditions
    private _wake = _task in _wakeTasks;

    if (!_wake && { _enemyPositions isNotEqualTo [] }) then {
        _wake = (_enemyPositions findIf { (_x distance2D _lpos) < _range }) > -1;
    };

    // parked groups can't see: one proximity query per parked group and cycle
    if (!_wake && { _isParked }) then {
        _wake = ((_leader nearEntities [_entityTypes, _range]) findIf {
            alive _x
            && {
                private _eSide = if (_x isKindOf "CAManBase") then { side group _x } else { side _x };
                _eSide in [west, east, independent, civilian]
                && { _eSide isNotEqualTo _side }
                && { (_side getFriend _eSide) < 0.6 }
            }
        }) > -1;
    };

    if (_wake) then {
        if (_isParked && { [_cmd, _grp, false] call AIC_fnc_setGroupSim }) then { _woken = _woken + 1; };
        continue;
    };

    // ---------------------------------------------------------- park conditions
    if (_isParked) then { continue };
    if !(_task in _parkTasks) then { continue };
    if ((behaviour _leader) isEqualTo "COMBAT") then { continue };

    private _taskPos = _rec getOrDefault ["taskPos", []];
    private _taskTime = _rec getOrDefault ["taskTime", 0];
    if !(_taskTime isEqualType 0) then { _taskTime = 0; };

    private _settled =
        (currentWaypoint _grp) >= (count waypoints _grp)
        || { _taskPos isEqualType [] && { count _taskPos >= 2 } && { (_taskPos distance2D _lpos) < 100 } }
        || { (time - _taskTime) > 120 };

    if (_settled && { [_cmd, _grp, true] call AIC_fnc_setGroupSim }) then { _parked = _parked + 1; };
} forEach _records;

if ((_parked + _woken) > 0 && { !isNil "AIC_debug" } && { AIC_debug isEqualTo true }) then {
    ["dynSimCycle %1: parked %2, woke %3, now parked %4/%5", [
        _side, _parked, _woken,
        { _x getOrDefault ["parked", false] } count _records, count _records
    ]] call AIC_fnc_log;
};

[_parked, _woken]
