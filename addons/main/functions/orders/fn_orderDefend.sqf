/*
 * Name: AIC_fnc_orderDefend
 * Description:
 *   Orders a group to defend a position. Type-aware:
 *     INF          : MOVE to the position, then HOLD. A scheduled helper
 *                    waits until the group arrives and sends every unit on
 *                    foot (except the leader) into building positions
 *                    (buildingPos) of nearby enterable buildings, spread
 *                    round-robin over buildings closest to the centre, and
 *                    doStops them there. Units without a free building
 *                    position stay with the leader at the HOLD waypoint.
 *                    The helper aborts if a new order is given
 *                    (group variable "AIC_orderToken" changes).
 *     MOTOR/MECH/
 *     ARMOR        : MOVE to a road-friendly position near the edge of the
 *                    area facing the closest direction of approach, then
 *                    HOLD, AWARE / YELLOW.
 *     HELI / PLANE : never garrisoned - LOITER waypoint circling the
 *                    position (radius 500 heli / 1200 plane).
 *     NAVAL        : MOVE + HOLD on water near the position, otherwise
 *                    hold where it is.
 *     STATIC/ARTY  : stay in place, AWARE / YELLOW, no waypoints.
 *
 * Parameters:
 *   0: GROUP  - group
 *   1: ARRAY  - position to defend
 *   2: NUMBER - (optional) defended area radius, default 150 (garrison
 *               search radius is capped at 200 m)
 *   3: STRING - (optional) group type from AIC_fnc_classifyGroup; "" = classify now
 *
 * Returns:
 *   BOOL - true if the order was applied
 *
 * Example:
 *   [_group, getPosATL _flag, 150] call AIC_fnc_orderDefend;
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_radius", 150, [0]],
    ["_type", "", [""]]
];

if (isNull _group || {count _pos < 2}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

if (_type isEqualTo "") then { _type = [_group] call AIC_fnc_classifyGroup; };
_radius = _radius max 30;
private _center = [_pos select 0, _pos select 1, 0];

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

// --- Static weapons / artillery: stay where they are ------------------------
if (_type in ["STATIC", "ARTY"]) exitWith {
    _group setBehaviour "AWARE";
    _group setCombatMode "YELLOW";
    true
};

private _token = [_group] call AIC_fnc_clearWaypoints;
_group allowFleeing 0;

// --- Air: loiter overhead, never garrison ----------------------------------
if (_type in ["HELI", "PLANE"]) exitWith {
    private _wp = _group addWaypoint [_center, 0];
    _wp setWaypointType "LOITER";
    _wp setWaypointLoiterType "CIRCLE_L";
    _wp setWaypointLoiterRadius (if (_type == "PLANE") then {1200} else {500});
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "RED";
    _wp setWaypointSpeed "NORMAL";
    _group setCurrentWaypoint _wp;
    true
};

// --- Naval -----------------------------------------------------------------
if (_type == "NAVAL") exitWith {
    private _water = [];
    if (surfaceIsWater _center) then {
        _water = _center;
    } else {
        for "_d" from 50 to 800 step 50 do {
            private _try = _center getPos [_d, _center getDir _leader];
            if (surfaceIsWater _try) exitWith { _water = [_try select 0, _try select 1, 0]; };
        };
    };
    if (_water isEqualTo []) exitWith {
        _group setBehaviour "AWARE";
        _group setCombatMode "YELLOW";
        true
    };
    private _wpM = _group addWaypoint [_water, 0];
    _wpM setWaypointType "MOVE";
    _wpM setWaypointBehaviour "AWARE";
    _wpM setWaypointSpeed "NORMAL";
    _wpM setWaypointCompletionRadius 60;
    private _wpH = _group addWaypoint [_water, 0];
    _wpH setWaypointType "HOLD";
    _wpH setWaypointCombatMode "YELLOW";
    _group setCurrentWaypoint _wpM;
    true
};

// --- Ground vehicles: hold a road-friendly spot on the threatened side -----
if (_type in ["MOTOR", "MECH", "ARMOR"]) exitWith {
    private _dir = _center getDir _leader;
    private _enemy = _leader findNearestEnemy _center;
    if (!isNull _enemy) then { _dir = _center getDir _enemy; };
    private _hold = _center getPos [(_radius * 0.5) min 150, _dir];
    _hold = [[_hold select 0, _hold select 1, 0], 120] call _fnc_roadPos;
    if (surfaceIsWater _hold) then { _hold = _center; };

    private _wpM = _group addWaypoint [_hold, 0];
    _wpM setWaypointType "MOVE";
    _wpM setWaypointBehaviour "AWARE";
    _wpM setWaypointCombatMode "YELLOW";
    _wpM setWaypointSpeed "NORMAL";
    _wpM setWaypointFormation (if (_type == "MOTOR") then {"COLUMN"} else {"WEDGE"});
    _wpM setWaypointCompletionRadius 40;
    private _wpH = _group addWaypoint [_hold, 0];
    _wpH setWaypointType "HOLD";
    _wpH setWaypointBehaviour "AWARE";
    _wpH setWaypointCombatMode "YELLOW";
    _wpH setWaypointCompletionRadius 40;
    _group setCurrentWaypoint _wpM;
    true
};

// --- Infantry: move, hold, garrison buildings -------------------------------
private _wpM = _group addWaypoint [_center, 0];
_wpM setWaypointType "MOVE";
_wpM setWaypointBehaviour "AWARE";
_wpM setWaypointCombatMode "YELLOW";
_wpM setWaypointSpeed "NORMAL";
_wpM setWaypointFormation "WEDGE";
_wpM setWaypointCompletionRadius 25;
private _wpH = _group addWaypoint [_center, 0];
_wpH setWaypointType "HOLD";
_wpH setWaypointBehaviour "AWARE";
_wpH setWaypointCombatMode "YELLOW";
_wpH setWaypointCompletionRadius 25;
_group setCurrentWaypoint _wpM;

[_group, _center, (_radius min 200), _token] spawn {
    params ["_group", "_center", "_radius", "_token"];

    private _fnc_valid = {
        !isNull _group
        && {(_group getVariable ["AIC_orderToken", 0]) == _token}
        && {({alive _x} count units _group) > 0}
    };

    // Wait for arrival (max 15 min)
    private _timeout = time + 900;
    waitUntil {
        sleep 3;
        !(call _fnc_valid)
        || {time > _timeout}
        || {(leader _group) distance2D _center < ((_radius * 0.5) max 50)}
    };
    if (!(call _fnc_valid) || {time > _timeout}) exitWith {};

    // Collect building positions, grouped per building, closest buildings first
    private _buildings = nearestObjects [_center, ["House", "Building"], _radius, true];
    private _perBuilding = [];
    {
        private _bps = (_x buildingPos -1) select { (_x select 0) != 0 || {(_x select 1) != 0} };
        if (_bps isNotEqualTo []) then { _perBuilding pushBack (_bps call BIS_fnc_arrayShuffle); };
    } forEach _buildings;
    if (_perBuilding isEqualTo []) exitWith {};

    private _leader = leader _group;
    private _garrison = (units _group) select {
        alive _x && {_x != _leader} && {vehicle _x == _x} && {!isPlayer _x}
    };
    if (_garrison isEqualTo []) exitWith {};

    // Round-robin over buildings so units spread out (max 4 per building)
    private _slots = [];
    private _round = 0;
    while {count _slots < count _garrison && {_round < 4}} do {
        {
            if (count _slots >= count _garrison) exitWith {};
            if (_round < count _x) then { _slots pushBack (_x select _round); };
        } forEach _perBuilding;
        _round = _round + 1;
    };
    if (_slots isEqualTo []) exitWith {};

    private _pending = [];
    {
        if (_forEachIndex >= count _slots) exitWith {};
        private _bp = _slots select _forEachIndex;
        _x doMove _bp;
        _x setVariable ["AIC_garrisonPos", _bp];
        _pending pushBack _x;
    } forEach _garrison;

    // Freeze each unit once it reached its position (max 120 s)
    private _end = time + 120;
    while {_pending isNotEqualTo [] && {time < _end} && {call _fnc_valid}} do {
        sleep 2;
        {
            private _u = _x;
            if (!alive _u) then {
                _pending deleteAt (_pending find _u);
            } else {
                private _bp = _u getVariable ["AIC_garrisonPos", getPosATL _u];
                if (unitReady _u || {(getPosATL _u) distance _bp < 2.5}) then {
                    doStop _u;
                    _u setUnitPos "UP";
                    _pending deleteAt (_pending find _u);
                };
            };
        } forEach +_pending;
    };
    if (call _fnc_valid) then {
        { if (alive _x) then { doStop _x; }; } forEach _pending;
    };
};

true
