/*
 * Name: AIC_fnc_orderAssault
 * Description:
 *   Orders one ground group as part of an assault (AIC_fnc_assaultFor). Every
 *   group gets a lane, so the assault comes in on a broad front and not as a
 *   crowd on one line.
 *   State "STAGE": move to its place in the assembly area and hold, vehicles
 *   120 m behind the infantry (record "staged", "stagePos").
 *   State "GO":
 *     INF          : to its line of departure, then seek and destroy at a
 *                    walk (speed LIMITED), COMBAT, in line. A flanking team
 *                    uses its flanking point as line of departure.
 *     Vehicles     : built-up objective with infantry in the assault: to an
 *                    overwatch position outside the town and hold there,
 *                    firing in support (record "overwatch"). Open ground, or
 *                    no infantry: to the line of departure, then seek and
 *                    destroy at a walk, so they do not race ahead.
 *
 * Parameters:
 *   0: GROUP   - group
 *   1: ARRAY   - objective position
 *   2: NUMBER  - objective radius
 *   3: STRING  - group type: "INF", "MOTOR", "MECH" or "ARMOR"
 *   4: ARRAY   - flanking point, [] for none
 *   5: HASHMAP - the assault
 *   6: HASHMAP - the group record
 *
 * Returns:
 *   BOOL - true if the order was applied
 *
 * Example:
 *   [_group, _pos, 300, "INF", [], _assault, _record] call AIC_fnc_orderAssault;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_radius", 300, [0]],
    ["_type", "INF", [""]],
    ["_via", [], [[]]],
    ["_assault", createHashMap, [createHashMap]],
    ["_record", createHashMap, [createHashMap]]
];

if (isNull _group || {count _pos < 2} || {count _assault == 0}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

private _target = [_pos select 0, _pos select 1, 0];
private _dir = _assault get "dir";
private _isInf = _type isEqualTo "INF";
private _formation = ["WEDGE", "STAG COLUMN"] select _isInf;

// a lane of its own: 0, +1, -1, +2, -2, ...
private _lane = _record getOrDefault ["assaultLane", 1e6];
if ((_record getOrDefault ["assaultId", ""]) isNotEqualTo (_assault get "id") || {_lane > 1e5}) then {
    private _n = _assault get "slots";
    _assault set ["slots", _n + 1];
    _lane = (ceil (_n / 2)) * ([-1, 1] select ((_n % 2) == 1));
    _record set ["assaultId", _assault get "id"];
    _record set ["assaultLane", _lane];
};

[_group] call AIC_fnc_clearWaypoints;
_group allowFleeing 0;
_group setBehaviour "AWARE";
_group setCombatMode "YELLOW";
_group setSpeedMode "NORMAL";

private _fnc_dry = {
    params ["_p"];
    if (surfaceIsWater _p) then {_target} else {[_p select 0, _p select 1, 0]}
};
private _fnc_wp = {
    params ["_p", "_wpType", "_beh", "_speed", "_form", "_done"];
    private _wp = _group addWaypoint [_p, 0];
    _wp setWaypointType _wpType;
    _wp setWaypointBehaviour _beh;
    _wp setWaypointCombatMode (["YELLOW", "RED"] select (_wpType isEqualTo "SAD"));
    _wp setWaypointSpeed _speed;
    _wp setWaypointFormation _form;
    _wp setWaypointCompletionRadius _done;
    _wp
};

// --- gather ------------------------------------------------------------------
if ((_assault get "state") isEqualTo "STAGE") exitWith {
    private _p = (_assault get "stage") getPos [_lane * AIC_ASSAULT_FRONT, _dir + 90];
    if !(_isInf) then {
        _p = _p getPos [120, _dir];
        _p = [[_p select 0, _p select 1, 0], 100] call AIC_fnc_roadPos;
    };
    _p = [_p] call _fnc_dry;
    private _wp = [_p, "MOVE", "AWARE", "NORMAL", _formation, 40] call _fnc_wp;
    [_p, "HOLD", "AWARE", "NORMAL", ["WEDGE", "LINE"] select _isInf, 40] call _fnc_wp;
    _group setCurrentWaypoint _wp;
    _record set ["staged", true];
    _record set ["stagePos", _p];
    true
};

_record set ["staged", false];
private _lanePos = {
    params ["_dist", "_spread"];
    [_target getPos [_dist, _dir + (_lane * _spread)]] call _fnc_dry
};

// --- vehicles watch over a built-up objective from outside --------------------
if (!_isInf && {_assault get "urban"} && {_assault get "hasInf"}) exitWith {
    private _p = [_radius + AIC_ASSAULT_OVERWATCH, 20] call _lanePos;
    private _wp = [_p, "MOVE", "AWARE", "LIMITED", "WEDGE", 40] call _fnc_wp;
    [_p, "HOLD", "AWARE", "LIMITED", "WEDGE", 40] call _fnc_wp;
    _group setCurrentWaypoint _wp;
    _record set ["overwatch", true];
    true
};

// --- in at a walk, on a broad front --------------------------------------------
private _start = if (count _via >= 2) then {[_via] call _fnc_dry} else {[_radius + 150 + (([50, 0] select _isInf)), 12] call _lanePos};
private _first = [];
if (count _via >= 2 || {(_leader distance2D _target) > (_radius + 200)}) then {
    _first = [_start, "MOVE", "AWARE", "LIMITED", "WEDGE", ([40, 25] select _isInf)] call _fnc_wp;
};
private _wpS = [[_radius * 0.3, 40] call _lanePos, "SAD", "COMBAT", "LIMITED", ["WEDGE", "LINE"] select _isInf, (_radius * 0.5) max 30] call _fnc_wp;
_group setCurrentWaypoint ([_first, _wpS] select (_first isEqualTo []));

true
