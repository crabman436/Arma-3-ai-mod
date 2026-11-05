/*
    Function: AIC_fnc_dynSimCycle

    Description:
        Parks idle groups and wakes groups the commander needs (server only),
        using AIC_fnc_setGroupSim. Runs only if setting "manageDynSim" is
        true; if it was turned off, every group AIC parked is woken once.

        A group is WOKEN if any of these holds:
          - its task is ATTACK, REINFORCE, RETREAT, SUPPORT, TRANSPORT,
            TRANSPORTED, RTB or SUPPLY;
          - a known enemy contact or threat cluster is within
            "dynSimWakeRange" of its leader;
          - the group was engaged in the last 120 s (record key
            "lastEngaged", stamped by the event handlers of
            AIC_fnc_attachGroupEHs, which also wake it the moment it
            happens);
          - (parked groups) a hostile unit is within the wake radius of
            its leader: "dynSimWakeRange" plus the distance an enemy moving
            at AIC_WAKE_SPEED covers in one "loopInterval", so a fast column
            cannot reach a frozen garrison between two checks. Parked groups
            are blind, so this is how they notice an enemy coming. The
            hostile positions are collected once per cycle (alive, not
            captive units of hostile sides, vehicle crews included) into a
            grid of wake-radius cells, so each group only tests the 3 x 3
            cells around it;
          - it is the picket of its objective: of the PATROL groups of an
            objective one (an awake one if there is) is never parked, so
            every patrolled place keeps eyes open.
        A group is PARKED if all of these hold:
          - its task is IDLE, DEFEND or PATROL;
          - it is not its objective's picket (above);
          - it has arrived: leader within 100 m of "taskPos", or within
            1.5 x the objective radius (min 100 m) of "taskPos" with no
            waypoint left or the task older than 120 s. Without a taskPos:
            no waypoint left, or task older than 120 s and not moved for
            120 s. A group still marching to a distant objective is never
            parked;
          - it is not in COMBAT behaviour;
          - infantry on DEFEND: its building occupation is done
            (AIC_fnc_monitorGarrison: all units placed or timed out for
            the current order), or the task is older than 1100 s, so units
            never freeze halfway to their building positions;
          - no wake condition applies, and no hostile unit is within
            the wake radius (the same proximity test as for parked
            groups, so a group is not parked only to be woken by the same
            enemy on the next cycle).
        Everything else is left as it is.

    Parameters:
        0: HASHMAP - commander

    Returns:
        ARRAY - [number of groups parked this cycle, number woken this cycle]

    Example:
        [_cmd] call AIC_fnc_dynSimCycle;
*/

#include "\z\aic\addons\main\script_component.hpp"

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
// non-positive range: use the default (an empty commander reads the defaults)
if (_range <= 0) then { _range = [createHashMap, "dynSimWakeRange"] call AIC_fnc_getSetting; };

private _wakeTasks = ["ATTACK", "REINFORCE", "RETREAT", "SUPPORT", "TRANSPORT", "TRANSPORTED", "RTB", "SUPPLY"];
private _parkTasks = ["IDLE", "DEFEND", "PATROL"];
private _defRadius = [_cmd, "objectiveRadius"] call AIC_fnc_getSetting;
private _GARRISON_WAIT = 1100; // s: an INF DEFEND group whose garrison never finished is parked anyway

// --- enemy positions the commander already knows about (contacts + cluster centres)
private _enemyPositions = (((_cmd getOrDefault ["knownEnemies", []]) + (_cmd getOrDefault ["threats", []])) select {
    _x isEqualType createHashMap && {
        private _p = _x getOrDefault ["pos", []];
        _p isEqualType [] && { count _p >= 2 }
    }
}) apply { _x get "pos" };

// --- every hostile unit, once per cycle (parked groups are blind, and a
// group must not be parked next to an enemy). Crews of vehicles are units
// too; captives (surrendered / captured) do not count. The wake radius
// covers what a fast enemy drives in one cycle; the positions go into a
// grid of cells one wake radius wide, so a group tests only the 3 x 3 cells
// around it instead of every hostile unit on the map.
private _interval = [_cmd, "loopInterval"] call AIC_fnc_getSetting;
private _wakeRange = _range + (_interval max 0) * AIC_WAKE_SPEED;
// positions into cells _size wide: [x cell, y cell] -> positions
private _fnc_grid = {
    params ["_positions", "_size"];
    private _grid = createHashMap;
    {
        private _key = [floor ((_x select 0) / _size), floor ((_x select 1) / _size)];
        private _cell = _grid getOrDefault [_key, []];
        if (_cell isEqualTo []) then { _grid set [_key, _cell]; };
        _cell pushBack _x;
    } forEach _positions;
    _grid
};
// is a position of the grid within _size of _p? (the 3 x 3 cells around it)
private _fnc_gridNear = {
    params ["_grid", "_size", "_p"];
    if (count _grid == 0) exitWith { false };
    private _cx = floor ((_p select 0) / _size);
    private _cy = floor ((_p select 1) / _size);
    private _found = false;
    for "_i" from -1 to 1 do {
        for "_j" from -1 to 1 do {
            private _cell = _grid getOrDefault [[_cx + _i, _cy + _j], []];
            if ((_cell findIf { (_x distance2D _p) < _size }) > -1) exitWith { _found = true; };
        };
        if (_found) exitWith {};
    };
    _found
};
private _hostile = [];
{
    if (alive _x && { !captive _x } && {
        private _eSide = side group _x;
        _eSide in [west, east, independent, civilian]
        && { _eSide isNotEqualTo _side }
        && { (_side getFriend _eSide) < AIC_HOSTILE_FRIEND }
    }) then {
        _hostile pushBack getPosATL _x;
    };
} forEach allUnits;
private _cells = [_hostile, _wakeRange] call _fnc_grid;
// the known enemy positions as well, in cells one _range wide
private _enemyCells = [_enemyPositions, _range] call _fnc_grid;

// --- one picket per patrolled objective stays awake (an awake patrol first)
private _pickets = createHashMap; // objective id -> [hashValue group, awake]
{
    private _grp = _x getOrDefault ["group", grpNull];
    private _obj = _x getOrDefault ["objective", ""];
    if (
        (_x getOrDefault ["task", ""]) isEqualTo "PATROL"
        && { _obj isEqualType "" } && { _obj isNotEqualTo "" }
        && { _grp isEqualType grpNull } && { !isNull _grp }
        && { !(_grp getVariable ["AIC_noDynSim", false]) }
        && { ({ alive _x } count (units _grp)) > 0 }
    ) then {
        private _awake = !dynamicSimulationEnabled _grp;
        private _cur = _pickets getOrDefault [_obj, []];
        if (_cur isEqualTo [] || { _awake && { !(_cur select 1) } }) then {
            _pickets set [_obj, [hashValue _grp, _awake]];
        };
    };
} forEach _records;

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

    if (!_wake) then {
        _wake = [_enemyCells, _range, _lpos] call _fnc_gridNear;
    };

    // engaged recently: the group event handlers (AIC_fnc_attachGroupEHs)
    // stamp "lastEngaged" on EnemyDetected / Hit / FiredNear / UnitKilled
    // and wake the group at once; this keeps it awake for the next 120 s
    if (!_wake) then {
        private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
        _wake = _engaged isEqualType 0 && { (time - _engaged) < 120 };
    };

    // parked groups can't see: hostile units close to the leader
    if (!_wake && { _isParked }) then {
        _wake = [_cells, _wakeRange, _lpos] call _fnc_gridNear;
    };

    // the picket of a patrolled objective keeps its eyes open
    if (!_wake && { _task isEqualTo "PATROL" }) then {
        _wake = ((_pickets getOrDefault [_rec getOrDefault ["objective", ""], [""]]) select 0) isEqualTo (hashValue _grp);
    };

    if (_wake) then {
        if (_isParked && { [_cmd, _grp, false] call AIC_fnc_setGroupSim }) then { _woken = _woken + 1; };
        continue;
    };

    // ---------------------------------------------------------- park conditions
    if (_isParked) then { continue };
    if !(_task in _parkTasks) then { continue };
    // a frozen anti-air vehicle cannot see aircraft coming
    if ((_rec getOrDefault ["antiAir", false]) isEqualTo true) then { continue };
    if ((behaviour _leader) isEqualTo "COMBAT") then { continue };

    private _taskPos = _rec getOrDefault ["taskPos", []];
    private _taskTime = _rec getOrDefault ["taskTime", 0];
    if !(_taskTime isEqualType 0) then { _taskTime = 0; };

    private _hasTaskPos = _taskPos isEqualType [] && { count _taskPos >= 2 };
    private _taskDist = if (_hasTaskPos) then { _taskPos distance2D _lpos } else { 1e10 };
    private _lastMove = _rec getOrDefault ["lastMoveTime", time];
    if !(_lastMove isEqualType 0) then { _lastMove = time; };

    // "at the task": within 1.5 x the objective radius (min 100 m) of taskPos
    private _nearR = 100;
    private _objId = _rec getOrDefault ["objective", ""];
    if (_objId isEqualType "" && { _objId isNotEqualTo "" }) then {
        private _objRec = [_cmd, _objId] call AIC_fnc_getObjective;
        if (count _objRec > 0) then {
            private _r = _objRec getOrDefault ["radius", _defRadius];
            if (_r isEqualType 0) then { _nearR = (_r * 1.5) max 100; };
        };
    };

    // Never park a group that is still on its way (a frozen group would never
    // arrive, and monitorOrders does not re-issue parked groups): with a task
    // position the leader must be at it; without one, waypoints done or no
    // movement for 120 s.
    private _wpDone = (currentWaypoint _grp) >= (count waypoints _grp);
    private _settled = if (_hasTaskPos) then {
        _taskDist < 100
        || { _taskDist < _nearR && { _wpDone || { (time - _taskTime) > 120 } } }
    } else {
        _wpDone || { (time - _taskTime) > 120 && { (time - _lastMove) > 120 } }
    };

    // infantry occupying buildings: only once every unit is in place
    if (_settled && { _task isEqualTo "DEFEND" } && { (_rec getOrDefault ["type", ""]) isEqualTo "INF" }) then {
        _settled = (time - _taskTime) > _GARRISON_WAIT
            || {
                (_rec getOrDefault ["garrisonDone", false]) isEqualTo true
                && { (_rec getOrDefault ["garrisonToken", -1]) isEqualTo (_grp getVariable ["AIC_orderToken", 0]) }
            };
    };

    // never park next to an enemy (it would be woken again next cycle and
    // flip between frozen and awake while the enemy closes in)
    if (_settled && { !([_cells, _wakeRange, _lpos] call _fnc_gridNear) } && { [_cmd, _grp, true] call AIC_fnc_setGroupSim }) then { _parked = _parked + 1; };
} forEach _records;

if ((_parked + _woken) > 0 && { !isNil "AIC_ns" } && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["dynSimCycle %1: parked %2, woke %3, now parked %4/%5", [
        _side, _parked, _woken,
        { _x getOrDefault ["parked", false] } count _records, count _records
    ]] call AIC_fnc_log;
};

[_parked, _woken]
