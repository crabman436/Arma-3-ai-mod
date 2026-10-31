/*
 * Name: AIC_fnc_orderDefend
 * Description:
 *   Orders a group to defend a position. Type-aware:
 *     INF          : MOVE to the position, then HOLD. Once the leader
 *                    has arrived, the commander cycle (AIC_fnc_monitorOrders
 *                    -> AIC_fnc_monitorGarrison -> AIC_fnc_garrisonBuildings)
 *                    hands every unit on foot a position (static weapons,
 *                    buildings, perimeter) and settles it there. No script
 *                    waits here: everything stays unscheduled.
 *     MOTOR/MECH/
 *     ARMOR        : MOVE to a road-friendly position near the edge of the
 *                    area on the threatened side (threat position, else the
 *                    nearest enemy the leader knows, else the side it comes
 *                    from; spread a little so several vehicles do not share
 *                    one spot), then HOLD, AWARE / YELLOW. With "rear" the
 *                    side away from the threat. The threatened bearing is
 *                    kept in the group variable "AIC_holdDir" (-1 if none)
 *                    so AIC_fnc_garrisonCycle can turn the group around.
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
 *   4: ARRAY   - (optional) position of the nearest threat, default [] (none)
 *   5: BOOL   - (optional) vehicles hold the rear instead, default false
 *   6: ARRAY  - (optional) parking place at a base (AIC_fnc_parkSlot): the
 *               vehicle drives there, holds, relaxed, and stops its engine
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
    ["_type", "", [""]],
    ["_threatPos", [], [[]]],
    ["_rear", false, [false]],
    ["_park", [], [[]]]
];

if (isNull _group || {count _pos < 2}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

if (_type isEqualTo "") then { _type = [_group] call AIC_fnc_classifyGroup; };
_radius = _radius max 30;
private _center = [_pos select 0, _pos select 1, 0];

// --- Static weapons / artillery: stay where they are ------------------------
if (_type in ["STATIC", "ARTY"]) exitWith {
    _group setBehaviour "AWARE";
    _group setCombatMode "YELLOW";
    true
};

[_group] call AIC_fnc_clearWaypoints;
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
    private _water = [_center, _leader, 800] call AIC_fnc_waterPos;
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

// --- Ground vehicles in the motor pool --------------------------------------
if (_type in ["MOTOR", "MECH", "ARMOR"] && {count _park >= 2}) exitWith {
    _group setVariable ["AIC_holdDir", -1];
    private _wpM = _group addWaypoint [_park, 0];
    _wpM setWaypointType "MOVE";
    _wpM setWaypointBehaviour "SAFE";
    _wpM setWaypointCombatMode "YELLOW";
    _wpM setWaypointSpeed "LIMITED";
    _wpM setWaypointFormation "COLUMN";
    _wpM setWaypointCompletionRadius 12;
    private _wpH = _group addWaypoint [_park, 0];
    _wpH setWaypointType "HOLD";
    _wpH setWaypointBehaviour "SAFE";
    _wpH setWaypointCombatMode "YELLOW";
    _wpH setWaypointCompletionRadius 12;
    _wpM setWaypointStatements ["true", "if (local this) then { (vehicle this) engineOn false; };"];
    _group setCurrentWaypoint _wpM;
    true
};

// --- Ground vehicles: hold a road-friendly spot on the threatened side -----
if (_type in ["MOTOR", "MECH", "ARMOR"]) exitWith {
    private _dir = _center getDir _leader;
    private _enemy = _leader findNearestEnemy _center;
    private _known = true;
    switch (true) do {
        case (count _threatPos >= 2): { _dir = _center getDir _threatPos; };
        case (!isNull _enemy): { _dir = _center getDir _enemy; };
        default { _known = false; };
    };
    _group setVariable ["AIC_holdDir", if (_known && {!_rear}) then {_dir} else {-1}];
    private _holdDir = if (_rear) then {_dir + 180} else {_dir + (random 70) - 35};
    private _hold = _center getPos [(_radius * 0.5) min 150, _holdDir];
    _hold = [[_hold select 0, _hold select 1, 0], 120] call AIC_fnc_roadPos;
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

// --- Infantry: move and hold (buildings: AIC_fnc_monitorGarrison) -----------
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

true
