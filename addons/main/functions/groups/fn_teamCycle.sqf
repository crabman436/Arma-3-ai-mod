/*
 * Name: AIC_fnc_teamCycle
 * Description:
 *   Puts squads back together (server only, setting "dynamicSquads").
 *   Teams of one squad (same "teamId", AIC_fnc_splitGroup) merge into the
 *   biggest of them once nobody is on a ride or in a fight (60 s without
 *   contact), they have the same task and objective, and their leaders are
 *   within AIC_TEAM_MERGE_RADIUS. Teams that never meet stop being teams
 *   AIC_TEAM_LIFETIME seconds after their last ride, and go on as ordinary
 *   groups. A team merged into a group on DEFEND has that group take its
 *   positions again, so everybody gets a place.
 *   Remnants: an infantry group shot down to AIC_REMNANT_SIZE men or fewer
 *   (from at least 4, so sniper and AT pairs are left alone) joins the
 *   nearest infantry group with room (AIC_SQUAD_MAX_SIZE) within
 *   AIC_REMNANT_JOIN_RADIUS.
 *   Groups flagged "AIC_exclude" / "AIC_noSplit", parked groups and groups
 *   with anybody in a vehicle never take part. A group left empty is deleted
 *   by its "Empty" handler.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - number of merges
 *
 * Example:
 *   [_cmd] call AIC_fnc_teamCycle;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};
if !(([_cmd, "dynamicSquads"] call AIC_fnc_getSetting) isEqualTo true) exitWith {0};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) exitWith {0};
private _side = _cmd getOrDefault ["side", sideUnknown];

private _fnc_size = {
    params ["_r"];
    {alive _x} count (units (_r get "group"))
};

// free to merge: infantry on foot, awake, under command, not fighting
private _fnc_free = {
    params ["_r"];
    private _grp = _r get "group";
    private _engaged = _r getOrDefault ["lastEngaged", -1e6];
    (_r getOrDefault ["type", ""]) isEqualTo "INF"
    && {!((_r getOrDefault ["task", ""]) in ["TRANSPORT", "TRANSPORTED", "RETREAT"])}
    && {!(_grp getVariable ["AIC_exclude", false])}
    && {!(_grp getVariable ["AIC_noSplit", false])}
    && {!dynamicSimulationEnabled _grp}
    && {!(_engaged isEqualType 0) || {(time - _engaged) > 60}}
    && {((units _grp) findIf {isPlayer _x || {alive _x && {!isNull objectParent _x}}}) < 0}
};

private _fnc_merge = {
    params ["_from", "_to"];
    private _fromGrp = _from get "group";
    private _toGrp = _to get "group";
    private _units = (units _fromGrp) select {alive _x};
    [_fromGrp] call AIC_fnc_clearWaypoints;
    _units joinSilent _toGrp;
    _units doFollow (leader _toGrp);
    _to set ["initialSize", (_to getOrDefault ["initialSize", 1]) + (_from getOrDefault ["initialSize", count _units])];
    _from set ["teamId", 0];
};

private _records = (values _groupData) select {
    _x isEqualType createHashMap
    && {(_x getOrDefault ["group", grpNull]) isEqualType grpNull}
    && {!isNull (_x getOrDefault ["group", grpNull])}
    && {([_x] call _fnc_size) > 0}
};

private _merges = 0;

// ------------------------------------------------------------ teams
private _teams = createHashMap;
{
    private _id = _x getOrDefault ["teamId", 0];
    if (_id > 0) then {
        private _list = _teams getOrDefault [_id, []];
        _list pushBack _x;
        _teams set [_id, _list];
    };
} forEach _records;

{
    private _list = _y;
    // the last team standing is an ordinary group again
    if (count _list < 2) then {
        (_list select 0) set ["teamId", 0];
        continue;
    };
    // the clock starts when the last ride has ended
    if ((_list findIf {(_x getOrDefault ["task", ""]) in ["TRANSPORT", "TRANSPORTED"]}) >= 0) then {
        {_x set ["teamTime", time]} forEach _list;
        continue;
    };

    // the biggest team takes the others in
    private _lead = _list select 0;
    {if (([_x] call _fnc_size) > ([_lead] call _fnc_size)) then {_lead = _x}} forEach _list;

    private _leadGrp = _lead get "group";
    private _joined = 0;
    if ([_lead] call _fnc_free) then {
        {
            private _rec = _x;
            if (
                (_rec get "group") isNotEqualTo _leadGrp
                && {[_rec] call _fnc_free}
                && {(_rec getOrDefault ["task", ""]) isEqualTo (_lead getOrDefault ["task", ""])}
                && {(_rec getOrDefault ["objective", ""]) isEqualTo (_lead getOrDefault ["objective", ""])}
                && {((leader (_rec get "group")) distance2D (leader _leadGrp)) < AIC_TEAM_MERGE_RADIUS}
            ) then {
                [_rec, _lead] call _fnc_merge;
                _joined = _joined + 1;
            };
        } forEach _list;
    };
    if (_joined > 0) then {
        _merges = _merges + _joined;
        ["%1: squad %2 is back together (%3 teams joined)", [_side, groupId _leadGrp, _joined]] call AIC_fnc_log;
        if (({(_x getOrDefault ["teamId", 0]) > 0} count _list) < 2) then {_lead set ["teamId", 0]};
        // positions again, so the newcomers get one as well
        if ((_lead getOrDefault ["task", ""]) isEqualTo "DEFEND") then {
            [_cmd, _leadGrp, "DEFEND", _lead getOrDefault ["taskPos", []], _lead getOrDefault ["objective", ""], true] call AIC_fnc_issueOrder;
        };
    };

    if ((time - (_lead getOrDefault ["teamTime", time])) > AIC_TEAM_LIFETIME) then {
        {_x set ["teamId", 0]} forEach _list;
    };
} forEach _teams;

// ------------------------------------------------------------ remnants
private _used = [];
{
    private _rec = _x;
    private _grp = _rec get "group";
    private _size = [_rec] call _fnc_size;
    if (
        _size > AIC_REMNANT_SIZE
        || {(_rec getOrDefault ["initialSize", 0]) < 4}
        || {(_rec getOrDefault ["teamId", 0]) > 0}
        || {_grp in _used}
        || {!([_rec] call _fnc_free)}
    ) then {continue};

    private _best = createHashMap;
    private _bestDist = AIC_REMNANT_JOIN_RADIUS;
    {
        private _other = _x;
        private _oGrp = _other get "group";
        private _d = (leader _oGrp) distance2D (leader _grp);
        if (
            _oGrp isNotEqualTo _grp
            && {_d < _bestDist}
            && {!(_oGrp in _used)}
            && {(([_other] call _fnc_size) + _size) <= AIC_SQUAD_MAX_SIZE}
            && {[_other] call _fnc_free}
        ) then {
            _bestDist = _d;
            _best = _other;
        };
    } forEach _records;
    if (count _best == 0) then {continue};

    private _toGrp = _best get "group";
    _rec set ["initialSize", _size];
    [_rec, _best] call _fnc_merge;
    _used pushBack _grp;
    _used pushBack _toGrp;
    _merges = _merges + 1;
    ["%1: remnant of group %2 (%3 units) joins group %4", [_side, groupId _grp, _size, groupId _toGrp]] call AIC_fnc_log;
} forEach _records;

_merges
