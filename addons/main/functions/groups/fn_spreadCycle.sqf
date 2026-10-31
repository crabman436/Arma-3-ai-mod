/*
 * Name: AIC_fnc_spreadCycle
 * Description:
 *   Breaks up crowds of infantry groups (server only, setting "spreadGroups").
 *   The order functions already give groups their own lanes and spots; this
 *   is the safety net for whatever still bunches up, such as groups meeting
 *   on a road or arriving at the same place.
 *   When AIC_CROWD_GROUPS or more infantry groups have their leaders within
 *   AIC_CROWD_RADIUS of each other, all but one of them walk
 *   AIC_CROWD_SPREAD metres apart in different directions (doMove on the
 *   leader; the group follows and its waypoints go on from there).
 *   Left alone: groups on a ride, waiting in an assembly area, parked, in
 *   vehicles, with a player, in contact in the last 60 s, or already taking
 *   up defensive positions. A group is moved at most once in
 *   AIC_CROWD_COOLDOWN seconds.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - number of groups moved
 *
 * Example:
 *   [_cmd] call AIC_fnc_spreadCycle;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};
if !(([_cmd, "spreadGroups"] call AIC_fnc_getSetting) isEqualTo true) exitWith {0};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith {0};

// [record, group, leader position] of everybody who may be moved
private _list = [];
{
    private _rec = _x;
    if !(_rec isEqualType createHashMap) then {continue};
    private _grp = _rec getOrDefault ["group", grpNull];
    if (isNull _grp || {(_rec getOrDefault ["type", ""]) isNotEqualTo "INF"}) then {continue};
    if !((_rec getOrDefault ["task", ""]) in ["IDLE", "ATTACK", "REINFORCE", "DEFEND", "PATROL", "RETREAT"]) then {continue};
    // waiting in an assembly area (a group still marching there may be spread)
    if ((_rec getOrDefault ["staged", false]) isEqualTo true
        && {count (_rec getOrDefault ["stagePos", []]) >= 2}
        && {((leader _grp) distance2D (_rec get "stagePos")) < 150}) then {continue};
    if (dynamicSimulationEnabled _grp) then {continue};
    private _leader = leader _grp;
    if (!alive _leader || {!isNull objectParent _leader}) then {continue};
    if (((units _grp) findIf {isPlayer _x}) >= 0) then {continue};
    private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
    if (_engaged isEqualType 0 && {(time - _engaged) < 60}) then {continue};
    // building positions are handed out: this order's garrison is under way
    if ((_rec getOrDefault ["task", ""]) isEqualTo "DEFEND"
        && {(_rec getOrDefault ["garrisonToken", -1]) isEqualTo (_grp getVariable ["AIC_orderToken", 0])}) then {continue};
    _list pushBack [_rec, _grp, getPosATL _leader];
} forEach (values _groupData);

private _moved = 0;
private _seen = [];
{
    _x params ["", "_grp", "_pos"];
    if (_grp in _seen) then {continue};

    private _crowd = _list select {
        !((_x select 1) in _seen) && {((_x select 2) distance2D _pos) < AIC_CROWD_RADIUS}
    };
    if (count _crowd < AIC_CROWD_GROUPS) then {continue};

    private _count = count _crowd;
    // the one nearest the middle of the crowd stays, the others fan out around it
    private _mid = [0, 0, 0];
    { _mid = _mid vectorAdd (_x select 2); } forEach _crowd;
    _mid = _mid vectorMultiply (1 / _count);
    private _order = [];
    { _order pushBack [(_x select 2) distance2D _mid, _forEachIndex]; } forEach _crowd;
    _order sort true;
    _crowd = _order apply { _crowd select (_x select 1) };
    _pos = _crowd select 0 select 2;
    private _start = random 360;
    {
        _x params ["_rec", "_member"];
        _seen pushBack _member;
        if (_forEachIndex > 0 && {(time - (_rec getOrDefault ["lastSpread", -1e6])) > AIC_CROWD_COOLDOWN}) then {
            private _p = _pos getPos [AIC_CROWD_SPREAD, _start + _forEachIndex * 360 / (_count - 1)];
            if (!surfaceIsWater _p) then {
                (leader _member) doMove [_p select 0, _p select 1, 0];
                _rec set ["lastSpread", time];
                _moved = _moved + 1;
            };
        };
    } forEach _crowd;

    ["%1: %2 infantry groups bunched up at %3, spreading out", [
        _cmd getOrDefault ["side", sideUnknown], _count, _pos apply {round _x}
    ]] call AIC_fnc_log;
} forEach _list;

_moved
