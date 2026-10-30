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
 *
 * Parameters:
 *   0: GROUP  - group
 *   1: ARRAY  - rally position
 *   2: STRING - (optional) group type from AIC_fnc_classifyGroup; "" = classify now
 *
 * Returns:
 *   BOOL - true if waypoints were created
 *
 * Example:
 *   [_group, _commander get "hq"] call AIC_fnc_orderRetreat;
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_type", "", [""]]
];

if (isNull _group || {count _pos < 2}) exitWith {false};
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

private _fnc_roadPos = {
    params ["_p", ["_r", 150]];
    private _roads = _p nearRoads _r;
    if (_roads isEqualTo []) exitWith {_p};
    private _best = objNull;
    private _bestD = 1e10;
    {
        private _d = _x distance2D _p;
        if (_d < _bestD) then { _bestD = _d; _best = _x; };
    } forEach _roads;
    private _rp = getPosATL _best;
    [_rp select 0, _rp select 1, 0]
};

private _isGroundVeh = _type in ["MOTOR", "MECH", "ARMOR"];

if (_type == "NAVAL" && {!surfaceIsWater _dest}) then {
    private _water = [];
    for "_d" from 50 to 1000 step 50 do {
        private _try = _dest getPos [_d, _dest getDir _leader];
        if (surfaceIsWater _try) exitWith { _water = [_try select 0, _try select 1, 0]; };
    };
    if (_water isNotEqualTo []) then { _dest = _water; };
};
if (_isGroundVeh) then { _dest = [_dest, 150] call _fnc_roadPos; };
// Land groups must not be sent into the sea
if (!(_type in ["NAVAL", "HELI", "PLANE"]) && {surfaceIsWater _dest}) then {
    _dest = [_pos select 0, _pos select 1, 0];
};

[_group] call AIC_fnc_clearWaypoints;

_group setBehaviour "CARELESS";
_group setCombatMode "GREEN";
_group setSpeedMode "FULL";

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

_group setCurrentWaypoint _wp;
true
