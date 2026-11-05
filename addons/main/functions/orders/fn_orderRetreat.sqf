/*
 * Name: AIC_fnc_orderRetreat
 * Description:
 *   Orders a group to fall back to a position (usually the commander HQ).
 *   Clears all waypoints, resets fleeing (allowFleeing 0 so the group
 *   retreats as a unit instead of scattering), and adds a FULL speed MOVE
 *   waypoint in CARELESS behaviour (combat mode GREEN - avoid engagement).
 *   On arrival the waypoint statement switches the group back to
 *   AWARE / YELLOW and a HOLD waypoint keeps it in place.
 *   Vehicles get a road-snapped destination, helicopters fly direct,
 *   naval groups only retreat to water. Static weapons and artillery
 *   cannot move and are just set to AWARE.
 *   Threat-avoiding route: with a threat position (4th parameter, else the
 *   group variable "AIC_retreatFrom" = [threatPos, time], which callers
 *   going through AIC_fnc_issueOrder set just before the order; it is
 *   consumed here and ignored when older than 5 s) a
 *   ground group (INF / MOTOR / MECH / ARMOR) first moves
 *   AIC_RETREAT_FIRST_LEG m straight away from the threat, then on to the
 *   rally position - unless the rally position is nearer than that leg or
 *   the leg would end in water. On arrival the group turns AWARE (waypoint
 *   statement); the garrison system takes it over from there (callers set
 *   the record's "home" to the rally objective when they order it).
 *
 * Parameters:
 *   0: GROUP  - group
 *   1: ARRAY  - rally position
 *   2: STRING - (optional) group type from AIC_fnc_classifyGroup; "" = classify now
 *   3: ARRAY  - (optional) threat position to get away from first, default []
 *
 * Returns:
 *   BOOL - true if waypoints were created
 *
 * Example:
 *   [_group, _commander get "hq"] call AIC_fnc_orderRetreat;
 *   [_group, _rallyPos, "INF", _threatPos] call AIC_fnc_orderRetreat;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_type", "", [""]],
    ["_fromPos", [], [[]]]
];

if (isNull _group) exitWith {false};
// a threat handed over by a caller that goes through AIC_fnc_issueOrder (3 params)
// ([threatPos, time]; only taken the moment it was set, a stale one from an
// order issueOrder skipped is ignored)
private _handed = _group getVariable ["AIC_retreatFrom", []];
_group setVariable ["AIC_retreatFrom", nil];
if (count _fromPos < 2 && {_handed isEqualType []} && {count _handed == 2}) then {
    _handed params [["_hPos", [], [[]]], ["_hTime", -1e6, [0]]];
    if (count _hPos >= 2 && {(time - _hTime) < 5}) then {_fromPos = _hPos};
};

if (count _pos < 2) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

if (_type isEqualTo "") then { _type = [_group] call AIC_fnc_classifyGroup; };
private _dest = [_pos select 0, _pos select 1, 0];

_group allowFleeing 0;

if (_type in ["STATIC", "ARTY"]) exitWith {
    _group setBehaviour "AWARE";
    _group setCombatMode "YELLOW";
    false
};

private _isGroundVeh = _type in ["MOTOR", "MECH", "ARMOR"];

if (_type == "NAVAL" && {!surfaceIsWater _dest}) then {
    private _water = [_dest, _leader, 1000] call AIC_fnc_waterPos;
    // no water near the rally point: a ship stays where it is, at sea
    _dest = [getPosATL _leader, _water] select (_water isNotEqualTo []);
    _dest = [_dest select 0, _dest select 1, 0];
};
if (_isGroundVeh) then { _dest = [_dest, 150] call AIC_fnc_roadPos; };
// infantry falling back does not end up on one spot
if (_type == "INF") then {
    private _p = _dest getPos [30 + random 120, random 360];
    _dest = [_p select 0, _p select 1, 0];
};
// Land groups must not be sent into the sea
if (!(_type in ["NAVAL", "HELI", "PLANE"]) && {surfaceIsWater _dest}) then {
    _dest = [_pos select 0, _pos select 1, 0];
};

[_group] call AIC_fnc_clearWaypoints;

_group setBehaviour "CARELESS";
_group setCombatMode "GREEN";
_group setSpeedMode "FULL";

// --- threat-avoiding first leg: straight away from the threat, then to the rally point
private _first = [];
if (count _fromPos >= 2 && {_type in ["INF", "MOTOR", "MECH", "ARMOR"]}) then {
    private _lPos = getPosATL _leader;
    private _away = _lPos getPos [AIC_RETREAT_FIRST_LEG, _fromPos getDir _lPos];
    _away = [_away select 0, _away select 1, 0];
    if ((_lPos distance2D _dest) > AIC_RETREAT_FIRST_LEG && {!surfaceIsWater _away}) then {
        _first = _group addWaypoint [_away, 0];
        _first setWaypointType "MOVE";
        _first setWaypointBehaviour "CARELESS";
        _first setWaypointCombatMode "GREEN";
        _first setWaypointSpeed "FULL";
        _first setWaypointFormation (if (_isGroundVeh) then {"COLUMN"} else {"FILE"});
        _first setWaypointCompletionRadius (if (_type == "INF") then {30} else {60});
    };
};

private _wp = _group addWaypoint [_dest, 0];
_wp setWaypointType "MOVE";
_wp setWaypointBehaviour "CARELESS";
_wp setWaypointCombatMode "GREEN";
_wp setWaypointSpeed "FULL";
_wp setWaypointFormation (if (_isGroundVeh) then {"COLUMN"} else {"FILE"});
_wp setWaypointCompletionRadius (if (_type == "INF") then {30} else {60});
_wp setWaypointStatements [
    "true",
    "if (local this) then { (group this) setBehaviour 'AWARE'; (group this) setCombatMode 'YELLOW'; (group this) setSpeedMode 'NORMAL'; };"
];

if (_type != "PLANE") then {
    private _wpH = _group addWaypoint [_dest, 0];
    _wpH setWaypointType "HOLD";
    _wpH setWaypointBehaviour "AWARE";
    _wpH setWaypointCombatMode "YELLOW";
    _wpH setWaypointCompletionRadius 40;
} else {
    private _wpL = _group addWaypoint [_dest, 0];
    _wpL setWaypointType "LOITER";
    _wpL setWaypointLoiterType "CIRCLE_L";
    _wpL setWaypointLoiterRadius 1200;
    _wpL setWaypointBehaviour "AWARE";
    _wpL setWaypointCombatMode "YELLOW";
};

_group setCurrentWaypoint ([_first, _wp] select (_first isEqualTo []));
true
