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
 *   7: NUMBER - (optional) infantry sector: bearing from the centre the
 *               group's part of the place lies on, -1 for any, default -1
 *   8: ARRAY  - (optional) infantry post (AIC_fnc_garrisonPost): where the
 *               group holds and takes its positions (the ground it covers
 *               is in the record, AIC_fnc_monitorOrders hands it on), [] =
 *               a spot off the centre on its sector, default []
 *   9: ARRAY  - (optional) vehicle posts (AIC_fnc_garrisonVehicles,
 *               [vehicle, post, facing] each, the leader's first): the
 *               leader's vehicle holds at its post, every other one drives
 *               to its own (AIC_fnc_monitorVehiclePosts settles them);
 *               [] = the group holds one road spot on the threatened side,
 *               default []
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
    ["_park", [], [[]]],
    ["_sector", -1, [0]],
    ["_post", [], [[]]],
    ["_vehPosts", [], [[]]]
];

if (isNull _group || {count _pos < 2}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

if (_type isEqualTo "") then { _type = [_group] call AIC_fnc_classifyGroup; };
_radius = _radius max 30;
private _center = [_pos select 0, _pos select 1, 0];

// --- Static weapons / artillery: stay where they are ------------------------
if (_type in ["STATIC", "ARTY"]) exitWith {
    [_group] call AIC_fnc_clearWaypoints;
    [_group, "setBehaviour", "AWARE"] call AIC_fnc_do;
    [_group, "setCombatMode", "YELLOW"] call AIC_fnc_do;
    true
};

[_group] call AIC_fnc_clearWaypoints;
[_group, "allowFleeing", 0] call AIC_fnc_do;

// --- Air: loiter overhead, never garrison ----------------------------------
if (_type in ["HELI", "PLANE"]) exitWith {
    private _wp = _group addWaypoint [_center, 0];
    _wp setWaypointType "LOITER";
    _wp setWaypointLoiterType "CIRCLE_L";
    _wp setWaypointLoiterRadius (if (_type == "PLANE") then {1200} else {500});
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "RED";
    _wp setWaypointSpeed "NORMAL";
    [_group, "setCurrentWaypoint", _wp] call AIC_fnc_do;
    true
};

// --- Naval -----------------------------------------------------------------
if (_type == "NAVAL") exitWith {
    private _water = [_center, _leader, 800] call AIC_fnc_waterPos;
    if (_water isEqualTo []) exitWith {
        [_group, "setBehaviour", "AWARE"] call AIC_fnc_do;
        [_group, "setCombatMode", "YELLOW"] call AIC_fnc_do;
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
    [_group, "setCurrentWaypoint", _wpM] call AIC_fnc_do;
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
    _wpM setWaypointStatements ["true", "if (local this) then { { if (!isNull objectParent _x) then { (objectParent _x) engineOn false; }; } forEach units group this; };"];
    [_group, "setCurrentWaypoint", _wpM] call AIC_fnc_do;
    true
};

// --- Ground vehicles with posts of their own (AIC_fnc_garrisonVehicles) ----
if (_type in ["MOTOR", "MECH", "ARMOR"] && {_vehPosts isNotEqualTo []}) exitWith {
    (_vehPosts select 0) params ["", "_lp", "_ldir"];
    _lp = [_lp select 0, _lp select 1, 0];
    // the side the group holds: its leader's post (AIC_fnc_garrisonCycle turns it round)
    _group setVariable ["AIC_holdDir", if (count _threatPos >= 2) then {_center getDir _threatPos} else {_center getDir _lp}];
    private _wpM = _group addWaypoint [_lp, 0];
    _wpM setWaypointType "MOVE";
    _wpM setWaypointBehaviour "AWARE";
    _wpM setWaypointCombatMode "YELLOW";
    _wpM setWaypointSpeed "NORMAL";
    _wpM setWaypointFormation "COLUMN";
    _wpM setWaypointCompletionRadius 15;
    private _wpH = _group addWaypoint [_lp, 0];
    _wpH setWaypointType "HOLD";
    _wpH setWaypointBehaviour "AWARE";
    _wpH setWaypointCombatMode "YELLOW";
    _wpH setWaypointCompletionRadius 15;
    [_group, "setCurrentWaypoint", _wpM] call AIC_fnc_do;
    // each vehicle keeps its post (after the clearing above, which wipes the
    // old ones); every other vehicle makes for its own: its crew is taken
    // out of the formation first (doStop), or the leader's hold would pull
    // the vehicle back on the way
    {
        _x params ["_veh", "_p", "_d"];
        if (!isNull _veh && {alive _veh}) then {
            _veh setVariable ["AIC_vehPost", [[_p select 0, _p select 1, 0], _d]];
            _veh setVariable ["AIC_vehPosted", false];
            _veh setVariable ["AIC_vehHeld", nil];
            _veh setVariable ["AIC_vehSlow", nil];
            if (_forEachIndex > 0) then {
                [(crew _veh) select {alive _x && {(group _x) isEqualTo _group} && {!isPlayer _x}}, "doStop"] call AIC_fnc_do;
                [_veh, "doMove", [_p select 0, _p select 1, 0]] call AIC_fnc_do;
            };
        };
    } forEach _vehPosts;
    // a move ends as a drive-through back into the formation: the watcher
    // halts each vehicle on its post the second it gets there
    if (count _vehPosts > 1) then {
        _group setVariable ["AIC_vehWatch", true];
        [_group, _group getVariable ["AIC_orderToken", 0]] spawn AIC_fnc_vehiclePostWatch;
    };
    true
};

// --- Ground vehicles: hold a road-friendly spot on the threatened side -----
if (_type in ["MOTOR", "MECH", "ARMOR"]) exitWith {
    private _dir = _center getDir _leader;
    private _enemy = [_leader, _center] call AIC_fnc_nearestEnemy;
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
    [_group, "setCurrentWaypoint", _wpM] call AIC_fnc_do;
    true
};

// --- Infantry: move and hold (buildings: AIC_fnc_monitorGarrison) -----------
// every group makes for its own part of the place, not for the very middle:
// its post (AIC_fnc_garrisonPost), else a spot on its sector
// (AIC_fnc_issueOrder), else any
private _spot = if (count _post >= 2) then {
    [_post select 0, _post select 1, 0]
} else {
    _center getPos [(_radius min 200) * (0.15 + random 0.25), [random 360, _sector] select (_sector >= 0)]
};
_spot = if (surfaceIsWater _spot) then {_center} else {[_spot select 0, _spot select 1, 0]};
private _wpM = _group addWaypoint [_spot, 0];
_wpM setWaypointType "MOVE";
_wpM setWaypointBehaviour "AWARE";
_wpM setWaypointCombatMode "YELLOW";
_wpM setWaypointSpeed "NORMAL";
_wpM setWaypointFormation "WEDGE";
_wpM setWaypointCompletionRadius 25;
private _wpH = _group addWaypoint [_spot, 0];
_wpH setWaypointType "HOLD";
_wpH setWaypointBehaviour "AWARE";
_wpH setWaypointCombatMode "YELLOW";
_wpH setWaypointCompletionRadius 25;
[_group, "setCurrentWaypoint", _wpM] call AIC_fnc_do;

true
