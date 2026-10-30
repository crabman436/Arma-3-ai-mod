/*
 * Name: AIC_fnc_orderReinforce
 * Description:
 *   Orders a group to reinforce a position: clears waypoints, moves at
 *   FULL speed in AWARE behaviour (COLUMN for vehicles, road-snapped
 *   destination short of the fight), then SEEK AND DESTROY at the
 *   position in COMBAT / RED. Helicopters and planes fly direct.
 *   Naval groups only use water positions. Static weapons and artillery
 *   cannot move and are only set to combat mode RED.
 *
 * Parameters:
 *   0: GROUP  - group
 *   1: ARRAY  - position to reinforce
 *   2: STRING - (optional) group type from AIC_fnc_classifyGroup; "" = classify now
 *
 * Returns:
 *   BOOL - true if waypoints were created
 *
 * Example:
 *   [_group, getPosATL leader _friendlyGroup] call AIC_fnc_orderReinforce;
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
private _target = [_pos select 0, _pos select 1, 0];

if (_type in ["STATIC", "ARTY"]) exitWith {
    _group setBehaviour "AWARE";
    _group setCombatMode "RED";
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
private _isAir = _type in ["HELI", "PLANE"];

if (_type == "NAVAL" && {!surfaceIsWater _target}) then {
    private _water = [];
    for "_d" from 50 to 1000 step 50 do {
        private _try = _target getPos [_d, _target getDir _leader];
        if (surfaceIsWater _try) exitWith { _water = [_try select 0, _try select 1, 0]; };
    };
    if (_water isNotEqualTo []) then { _target = _water; };
};
if (_type == "NAVAL" && {!surfaceIsWater _target}) exitWith { false };

[_group] call AIC_fnc_clearWaypoints;
_group allowFleeing 0;
_group setCombatMode "YELLOW";

private _first = [];
private _dist = (getPosATL _leader) distance2D _target;

// Fast move to a staging point short of the fight
private _stageDist = switch (true) do {
    case (_type == "INF"): {150};
    case (_isGroundVeh): {350};
    case (_type == "HELI"): {600};
    default {0};
};
if (_stageDist > 0 && {_dist > _stageDist + 150}) then {
    private _stage = _target getPos [_stageDist, _target getDir _leader];
    _stage = [_stage select 0, _stage select 1, 0];
    if (_isGroundVeh) then { _stage = [_stage, 200] call _fnc_roadPos; };
    if (!_isAir && {_type != "NAVAL"} && {surfaceIsWater _stage}) then { _stage = _target; };
    private _wpM = _group addWaypoint [_stage, 0];
    _wpM setWaypointType "MOVE";
    _wpM setWaypointBehaviour "AWARE";
    _wpM setWaypointCombatMode "YELLOW";
    _wpM setWaypointSpeed "FULL";
    _wpM setWaypointFormation (if (_isGroundVeh) then {"COLUMN"} else {"WEDGE"});
    _wpM setWaypointCompletionRadius (if (_type == "INF") then {25} else {60});
    _first = _wpM;
};

private _wpS = _group addWaypoint [_target, 0];
_wpS setWaypointType "SAD";
_wpS setWaypointBehaviour "COMBAT";
_wpS setWaypointCombatMode "RED";
_wpS setWaypointSpeed (if (_isAir) then {"FULL"} else {"NORMAL"});
_wpS setWaypointFormation (if (_type == "INF") then {"LINE"} else {"WEDGE"});
_wpS setWaypointCompletionRadius 75;

if (_first isEqualTo []) then { _first = _wpS; };
_group setCurrentWaypoint _first;
true
