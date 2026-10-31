/*
 * Name: AIC_fnc_orderPatrol
 * Description:
 *   Orders a group to patrol an area: 4-5 random MOVE waypoints within the
 *   radius plus a CYCLE waypoint, SAFE (infantry / vehicles) or AWARE (air)
 *   behaviour, LIMITED speed. Type-aware:
 *     INF          : random land points, STAG COLUMN
 *     MOTOR/MECH/
 *     ARMOR        : points snapped to nearby roads, COLUMN
 *     HELI         : radius at least 600, AWARE, NORMAL speed
 *     PLANE        : single LOITER waypoint (radius at least 1500)
 *     NAVAL        : random water points only
 *     STATIC/ARTY  : no waypoints, AWARE
 *   Waypoint positions on water are rejected for land groups (and land
 *   positions for naval groups); if no valid point is found the group
 *   just moves to the centre and holds.
 *
 * Parameters:
 *   0: GROUP  - group
 *   1: ARRAY  - patrol centre
 *   2: NUMBER - (optional) patrol radius, default 300
 *   3: STRING - (optional) group type from AIC_fnc_classifyGroup; "" = classify now
 *   4: ARRAY  - (optional) a next objective ground vehicles drive to, default []
 *
 * Returns:
 *   BOOL - true if waypoints were created
 *
 * Example:
 *   [_group, getPosATL _town, 400] call AIC_fnc_orderPatrol;
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_radius", 300, [0]],
    ["_type", "", [""]],
    ["_link", [], [[]]]
];

if (isNull _group || {count _pos < 2}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

if (_type isEqualTo "") then { _type = [_group] call AIC_fnc_classifyGroup; };
_radius = _radius max 50;
private _center = [_pos select 0, _pos select 1, 0];

if (_type in ["STATIC", "ARTY"]) exitWith {
    _group setBehaviour "AWARE";
    _group setCombatMode "YELLOW";
    false
};

[_group] call AIC_fnc_clearWaypoints;

if (_type == "PLANE") exitWith {
    private _wp = _group addWaypoint [_center, 0];
    _wp setWaypointType "LOITER";
    _wp setWaypointLoiterType "CIRCLE_L";
    _wp setWaypointLoiterRadius (_radius max 1500);
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "YELLOW";
    _wp setWaypointSpeed "NORMAL";
    _group setCurrentWaypoint _wp;
    true
};

private _isAir = _type == "HELI";
private _isNaval = _type == "NAVAL";
private _isGroundVeh = _type in ["MOTOR", "MECH", "ARMOR"];
if (_isAir) then { _radius = _radius max 600; };

private _behaviour = if (_isAir) then {"AWARE"} else {"SAFE"};
private _speed = if (_isAir) then {"NORMAL"} else {"LIMITED"};
private _formation = switch (true) do {
    case (_isGroundVeh): {"COLUMN"};
    case (_type == "INF"): {"STAG COLUMN"};
    default {"WEDGE"};
};

// A route around the place, not a random walk through it: 5-6 points on a ring
// at about the edge, in order, starting on the side the group is on
private _points = [];
private _wanted = 5 + floor random 2;
private _start = _center getDir _leader;
private _turn = selectRandom [1, -1];
for "_i" from 0 to (_wanted - 1) do {
    private _p = _center getPos [_radius * (0.85 + random 0.3), _start + _turn * _i * 360 / _wanted];
    _p = [_p select 0, _p select 1, 0];
    if (_isGroundVeh) then { _p = [_p, 150] call AIC_fnc_roadPos; };
    private _wet = surfaceIsWater _p;
    private _ok = switch (true) do {
        case (_isAir): {true};
        case (_isNaval): {_wet};
        default {!_wet};
    };
    if (_ok && {(_points findIf {_x distance2D _p < (_radius * 0.25)}) < 0}) then {
        _points pushBack _p;
    };
};

// an armed car goes on to the next objective and back
if (_isGroundVeh && {count _link >= 2} && {_points isNotEqualTo []}) then {
    private _p = [[_link select 0, _link select 1, 0], 200] call AIC_fnc_roadPos;
    if (!surfaceIsWater _p) then { _points pushBack _p; };
};

if (_points isEqualTo []) exitWith {
    private _wp = _group addWaypoint [_center, 0];
    _wp setWaypointType "MOVE";
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCompletionRadius 30;
    private _wpH = _group addWaypoint [_center, 0];
    _wpH setWaypointType "HOLD";
    _group setCurrentWaypoint _wp;
    false
};

private _first = [];
{
    private _wp = _group addWaypoint [_x, 0];
    _wp setWaypointType "MOVE";
    _wp setWaypointBehaviour _behaviour;
    _wp setWaypointCombatMode "YELLOW";
    _wp setWaypointSpeed _speed;
    _wp setWaypointFormation _formation;
    _wp setWaypointCompletionRadius (if (_isGroundVeh || _isAir || _isNaval) then {50} else {20});
    // infantry stops and looks around at each point
    if (_type == "INF") then { _wp setWaypointTimeout [10, 20, 40]; };
    if (_forEachIndex == 0) then { _first = _wp; };
} forEach _points;

private _wpC = _group addWaypoint [_points select 0, 0];
_wpC setWaypointType "CYCLE";
_wpC setWaypointCompletionRadius 50;

_group setCurrentWaypoint _first;
true
