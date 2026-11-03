/*
 * Name: AIC_fnc_orderRecon
 * Description:
 *   Sends a group to watch an objective from outside (task "RECON", given
 *   by AIC_fnc_allocateForces before a new attack on an objective nobody has
 *   looked at for a while). The overwatch point lies AIC_RECON_STANDOFF_MIN
 *   to AIC_RECON_STANDOFF_MAX m from the objective (at least radius + 250 /
 *   radius + 550 m for big objectives), on the side the group comes from or
 *   swung up to 90 degrees around it, on high ground at the edge of the
 *   woods with a terrain line of sight to the objective (AIC_fnc_bestPlace,
 *   the terrain scoring every position search uses; vehicles keep out of
 *   the forest). Without a spot that sees the objective, the best cover in
 *   the band is taken, else the middle of the band.
 *   Waypoints: a long way starts with a MOVE to a point 400 m short (AWARE,
 *   NORMAL), then a MOVE to the point in STEALTH at a walk, an UNLOAD there
 *   when the group drives its own vehicles (the infantry it carries
 *   dismounts, the vehicles stay), then HOLD in STEALTH. Combat mode GREEN
 *   throughout: the group defends itself but does not open fire.
 *   Writes the record keys "reconPos" (the overwatch point) and
 *   "reconArrive" (-1: not there yet; AIC_fnc_monitorOrders sets the time).
 *
 * Parameters:
 *   0: GROUP   - group
 *   1: ARRAY   - objective position
 *   2: NUMBER  - (optional) objective radius, default 300
 *   3: STRING  - (optional) group type, "" = classify now, default ""
 *   4: HASHMAP - (optional) the group record, default none
 *
 * Returns:
 *   BOOL - true if the waypoints were created
 *
 * Example:
 *   [_group, _obj get "pos", _obj get "radius", "MOTOR", _record] call AIC_fnc_orderRecon;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_radius", 300, [0]],
    ["_type", "", [""]],
    ["_record", createHashMap, [createHashMap]]
];

if (isNull _group || {count _pos < 2}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};
if (_type isEqualTo "") then {_type = [_group] call AIC_fnc_classifyGroup};
if (_type in ["STATIC", "ARTY", "NAVAL"]) exitWith {false};

private _target = [_pos select 0, _pos select 1, 0];
private _dMin = AIC_RECON_STANDOFF_MIN max (_radius + 250);
private _dMax = AIC_RECON_STANDOFF_MAX max (_radius + 550);
private _dMid = (_dMin + _dMax) / 2;
private _band = (_dMax - _dMin) / 2;
private _dir = _target getDir _leader;

// does the group drive vehicles of its own (MOTOR: the infantry rides along)?
private _vehicles = [];
{
    private _veh = objectParent _x;
    if (alive _x && {!isNull _veh} && {_veh isKindOf "LandVehicle"} && {(group (driver _veh)) isEqualTo _group}) then {
        _vehicles pushBackUnique _veh;
    };
} forEach (units _group);
private _mounted = _vehicles isNotEqualTo [];
private _carries = _mounted && {((units _group) findIf {alive _x && {((assignedVehicleRole _x) param [0, ""]) == "cargo"}}) >= 0};
// high ground at the edge of the woods; vehicles cannot get into the forest
private _expression = ["2*hills + forest + trees - 2*houses - 10*sea", "2*hills + trees - forest - 2*houses - 10*sea"] select _mounted;

// a spot in the band that sees the objective, on the near side first
private _spot = [];
private _cover = [];
{
    private _c = _target getPos [_dMid, _dir + _x];
    if (surfaceIsWater _c) then {continue};
    private _p = [_c, _band, _expression, 0, _target] call AIC_fnc_bestPlace;
    if (_p isNotEqualTo [] && {(_p distance2D _target) >= (_dMin - 50)} && {(_p distance2D _target) <= (_dMax + 50)}) exitWith {_spot = _p};
    if (_cover isEqualTo []) then {
        _cover = [_c, _band, _expression] call AIC_fnc_bestPlace;
        if (_cover isEqualTo []) then {_cover = [_c select 0, _c select 1, 0]};
    };
} forEach [0, 30, -30, 60, -60, 90, -90];
if (_spot isEqualTo []) then {_spot = _cover};
if (_spot isEqualTo []) then {
    private _c = _target getPos [_dMid, _dir];
    _spot = [_c select 0, _c select 1, 0];
};

[_group] call AIC_fnc_clearWaypoints;
_group allowFleeing 0;
_group setBehaviour "AWARE";
_group setCombatMode "GREEN";
_group setSpeedMode "NORMAL";

private _fnc_wp = {
    params ["_p", "_wpType", "_beh", "_speed", "_done"];
    private _wp = _group addWaypoint [_p, 0];
    _wp setWaypointType _wpType;
    _wp setWaypointBehaviour _beh;
    _wp setWaypointCombatMode "GREEN";
    _wp setWaypointSpeed _speed;
    _wp setWaypointFormation (["STAG COLUMN", "WEDGE"] select _mounted);
    _wp setWaypointCompletionRadius _done;
    _wp
};

// the last stretch is crept up on, the way there is not
private _first = [];
private _way = _leader distance2D _spot;
if (_way > 800) then {
    private _short = _spot getPos [400, _spot getDir _leader];
    if (!surfaceIsWater _short) then {
        _first = [[_short select 0, _short select 1, 0], "MOVE", "AWARE", "NORMAL", 60] call _fnc_wp;
    };
};
private _wpAt = [_spot, "MOVE", "STEALTH", "LIMITED", 30] call _fnc_wp;
if (_carries) then {[_spot, "UNLOAD", "STEALTH", "LIMITED", 30] call _fnc_wp};
[_spot, "HOLD", "STEALTH", "LIMITED", 30] call _fnc_wp;
_group setCurrentWaypoint ([_first, _wpAt] select (_first isEqualTo []));

if (count _record > 0) then {
    _record set ["reconPos", _spot];
    _record set ["reconArrive", -1];
};

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["orderRecon: group %1 (%2) watches %3 from %4, %5 m out", [
        groupId _group, _type, _target apply {round _x}, _spot apply {round _x}, round (_spot distance2D _target)
    ]] call AIC_fnc_log;
};

true
