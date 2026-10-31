/*
 * Name: AIC_fnc_orderAttack
 * Description:
 *   Orders a group to attack an area. Clears existing waypoints, then
 *   adds a type-aware MOVE approach waypoint short of the target and a
 *   SEEK AND DESTROY waypoint at the target.
 *     INF          : approach 250 m out, WEDGE, AWARE -> SAD COMBAT/RED
 *     MOTOR        : road-snapped approach 450 m out (dismount/stand-off),
 *                    COLUMN, AWARE, NORMAL -> SAD COMBAT/RED
 *     MECH / ARMOR : road-snapped approach 600 m out, WEDGE, AWARE ->
 *                    SAD COMBAT/RED, LIMITED speed to keep formation
 *     HELI         : direct MOVE 800 m out, then SAD (FULL speed)
 *     PLANE        : direct SAD over target (FULL speed)
 *     NAVAL        : MOVE/SAD only on water positions
 *     STATIC/ARTY  : cannot manoeuvre -> only combat mode RED, no waypoints
 *   The approach waypoint is skipped when the group is already close.
 *
 * Parameters:
 *   0: GROUP  - attacking group
 *   1: ARRAY  - target position [x,y] or [x,y,z]
 *   2: NUMBER - (optional) target area radius, default 150
 *   3: STRING - (optional) group type from AIC_fnc_classifyGroup; "" = classify now
 *
 * Returns:
 *   BOOL - true if waypoints were created
 *
 * Example:
 *   [_group, getMarkerPos "target", 200] call AIC_fnc_orderAttack;
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_radius", 150, [0]],
    ["_type", "", [""]],
    ["_via", [], [[]]]
];

if (isNull _group || {count _pos < 2}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

if (_type isEqualTo "") then { _type = [_group] call AIC_fnc_classifyGroup; };
_radius = _radius max 50;
private _target = [_pos select 0, _pos select 1, 0];

// Static / artillery cannot attack by moving
if (_type in ["STATIC", "ARTY"]) exitWith {
    _group setCombatMode "RED";
    _group setBehaviour "AWARE";
    false
};

[_group] call AIC_fnc_clearWaypoints;

if (_type == "NAVAL" && {!surfaceIsWater _target}) exitWith {
    // Boats engage from the closest water we can find towards the target
    private _water = [_target, _leader, 1000] call AIC_fnc_waterPos;
    if (_water isEqualTo []) exitWith {false};
    private _wp = _group addWaypoint [_water, 0];
    _wp setWaypointType "SAD";
    _wp setWaypointBehaviour "COMBAT";
    _wp setWaypointCombatMode "RED";
    _wp setWaypointSpeed "NORMAL";
    _wp setWaypointCompletionRadius 100;
    _group setCurrentWaypoint _wp;
    true
};

private _approachDist = switch (_type) do {
    case "INF":   {250};
    case "MOTOR": {450};
    case "MECH";
    case "ARMOR": {600};
    case "HELI":  {800};
    default       {0};
};
private _formation = switch (_type) do {
    case "INF":   {"WEDGE"};
    case "MOTOR": {"COLUMN"};
    case "MECH";
    case "ARMOR": {"WEDGE"};
    default       {"WEDGE"};
};
private _isGroundVeh = _type in ["MOTOR", "MECH", "ARMOR"];
private _isAir = _type in ["HELI", "PLANE"];

_group setFormation _formation;
_group setCombatMode "YELLOW";
_group allowFleeing 0;

private _leaderPos = getPosATL _leader;
private _dist = _leaderPos distance2D _target;

private _first = [];

// Approach waypoint
if (count _via >= 2 || {_approachDist > 0 && {_dist > (_approachDist + _radius + 100)}}) then {
    // (infantry from one place does not come in on one line)
    private _approachDir = (_target getDir _leaderPos) + (if (_type == "INF") then {(random 60) - 30} else {0});
    private _app = if (count _via >= 2) then {_via} else {_target getPos [_approachDist + (_radius * 0.5), _approachDir]};
    _app = [_app select 0, _app select 1, 0];
    if (_isGroundVeh) then { _app = [_app, 200] call AIC_fnc_roadPos; };
    if (surfaceIsWater _app && {!_isAir}) then {
        _app = _target getPos [_approachDist * 0.5, _target getDir _leaderPos];
        _app = [_app select 0, _app select 1, 0];
    };
    private _wpA = _group addWaypoint [_app, 0];
    _wpA setWaypointType "MOVE";
    _wpA setWaypointBehaviour "AWARE";
    _wpA setWaypointCombatMode "YELLOW";
    _wpA setWaypointSpeed (if (_isAir) then {"FULL"} else {"NORMAL"});
    _wpA setWaypointFormation _formation;
    _wpA setWaypointCompletionRadius (if (_isGroundVeh || _isAir) then {60} else {25});
    _first = _wpA;
};

// Seek and destroy at target
private _sadPos = _target;
if (_type == "INF") then {
    // spread infantry a bit inside the area
    private _p = _target getPos [random (_radius * 0.5), random 360];
    if (!surfaceIsWater _p) then { _sadPos = [_p select 0, _p select 1, 0]; };
};
private _wpS = _group addWaypoint [_sadPos, 0];
_wpS setWaypointType "SAD";
_wpS setWaypointBehaviour "COMBAT";
_wpS setWaypointCombatMode "RED";
_wpS setWaypointSpeed (switch (true) do {
    case (_isAir): {"FULL"};
    case (_type in ["MECH", "ARMOR"]): {"LIMITED"};
    default {"NORMAL"};
});
_wpS setWaypointFormation (if (_type == "INF") then {"LINE"} else {_formation});
_wpS setWaypointCompletionRadius ((_radius * 0.5) max 30);

if (_first isEqualTo []) then { _first = _wpS; };
_group setCurrentWaypoint _first;
true
