/*
 * Name: AIC_fnc_splitGroup
 * Description:
 *   Splits an infantry group into teams (server only, setting "dynamicSquads").
 *   The original group keeps its leader and the first team; every other team
 *   becomes a new group with a complete record, commanded at once. Units are
 *   dealt out in squad order, so machine gunners and AT specialists spread
 *   over the teams instead of ending up in one. All teams share a "teamId"
 *   (AIC_fnc_teamCycle merges them again), and "initialSize" and "power" are
 *   shared out too, so a team does not look like a shot-up squad and retreat.
 *   Refused for groups that are not infantry, not local, have a player, have
 *   anybody in a vehicle, are flagged "AIC_exclude" / "AIC_noSplit", already
 *   are teams, or would leave a team below AIC_TEAM_MIN_SIZE.
 *   Every team has its waypoints cleared and holds until it gets an order:
 *   the caller orders the original group and the new ones.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - group to split
 *   2: NUMBER  - (optional) number of teams, default 2
 *
 * Returns:
 *   ARRAY - the new groups, [] if the group was not split
 *
 * Example:
 *   private _new = [_cmd, _squad, 2] call AIC_fnc_splitGroup;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_teams", 2, [0]]
];

if (!isServer) exitWith {[]};
if (count _cmd == 0 || {isNull _group} || {!local _group}) exitWith {[]};
if !(([_cmd, "dynamicSquads"] call AIC_fnc_getSetting) isEqualTo true) exitWith {[]};
if (_group getVariable ["AIC_exclude", false] || {_group getVariable ["AIC_noSplit", false]}) exitWith {[]};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _rec = _groupData getOrDefault [hashValue _group, createHashMap];
if (count _rec == 0 || {(_rec getOrDefault ["type", ""]) isNotEqualTo "INF"}) exitWith {[]};
if ((_rec getOrDefault ["teamId", 0]) > 0) exitWith {[]};

private _leader = leader _group;
private _alive = (units _group) select {alive _x};
private _total = count _alive;
_teams = round _teams;
if (_teams < 2 || {_total < (_teams * AIC_TEAM_MIN_SIZE)}) exitWith {[]};
if ((_alive findIf {isPlayer _x || {!isNull objectParent _x}}) >= 0) exitWith {[]};

private _side = _cmd getOrDefault ["side", sideUnknown];
if ((count (groups _side)) + _teams - 1 > AIC_MAX_SIDE_GROUPS) exitWith {[]};

// releases building positions, static guns and doStop before anybody leaves
[_cmd, _group, false] call AIC_fnc_setGroupSim;
[_group] call AIC_fnc_clearWaypoints;

// deal the units out, the leader first so he stays with the original group
private _dealt = (_alive select {_x isEqualTo _leader}) + (_alive - [_leader]);
private _buckets = [];
for "_t" from 1 to _teams do {_buckets pushBack []};
{(_buckets select (_forEachIndex % _teams)) pushBack _x} forEach _dealt;

private _teamId = (_cmd getOrDefault ["teamCounter", 0]) + 1;
_cmd set ["teamCounter", _teamId];

private _oldInitial = (_rec getOrDefault ["initialSize", _total]) max _total;
private _oldPower = _rec getOrDefault ["power", 0];
private _oldStrength = _rec getOrDefault ["strength", 1];

private _fnc_stamp = {
    params ["_r", "_size"];
    _r set ["teamId", _teamId];
    _r set ["teamTime", time];
    _r set ["lastSplit", time];
    _r set ["initialSize", (round (_oldInitial * _size / _total)) max _size];
    _r set ["power", _oldPower * _size / _total];
    _r set ["strength", _oldStrength];
};

private _new = [];
for "_t" from 1 to (_teams - 1) do {
    private _team = _buckets select _t;
    private _grp = createGroup [_side, true];
    if (isNull _grp) then {continue};
    _team joinSilent _grp;
    {_grp setVariable [_x, _group getVariable [_x, false]]} forEach ["AIC_noDynSim", "AIC_keep"];

    private _r = [_grp] call AIC_fnc_newGroupRecord;
    _r set ["home", _rec getOrDefault ["home", ""]];
    _r set ["rideAbortTime", _rec getOrDefault ["rideAbortTime", -1e6]];
    [_r, count _team] call _fnc_stamp;
    _groupData set [hashValue _grp, _r];
    [_cmd, _grp] call AIC_fnc_attachGroupEHs;
    _cmd set ["groups", (_cmd getOrDefault ["groups", []]) + [_grp]];
    _new pushBack _grp;
};

if (_new isEqualTo []) exitWith {[]};
[_rec, {alive _x} count (units _group)] call _fnc_stamp;

["%1: group %2 split into %3 teams (%4 units): %5", [
    _side, groupId _group, 1 + count _new, _total, _new apply {groupId _x}
]] call AIC_fnc_log;

_new
