/*
 * Name: AIC_fnc_monitorVehiclePosts
 * Description:
 *   Settles a ground vehicle group on the posts AIC_fnc_garrisonVehicles
 *   handed out (called by AIC_fnc_monitorOrders for every awake MOTOR /
 *   MECH / ARMOR DEFEND group whose record says "vehPosts"), one step per
 *   commander cycle, nothing scheduled. The state lives in the group record
 *   under the garrison keys and is valid while "garrisonToken" equals the
 *   group variable "AIC_orderToken" (a new order starts over):
 *     - first call for an order: "garrisonToken" / "garrisonTime" are set.
 *     - every vehicle with a post ("AIC_vehPost") that is at it (within
 *       AIC_VEHPOST_NEAR), or that stopped short of it (speed under 0.5;
 *       sent once more after 30 s, then left where it stands after 90 s),
 *       or whose AIC_VEHPOST_TIMEOUT s are up, is posted ("AIC_vehPosted"):
 *       stopped (doStop; the leader's vehicle keeps its HOLD waypoint
 *       instead), watching the threat, or out along its facing without
 *       one, and its engine is stopped while no threat is known.
 *     - once every vehicle is posted, the men riding in cargo (not the
 *       crew) get out (unit variable "AIC_dismounted" = their vehicle;
 *       AIC_fnc_clearWaypoints puts them back in on the next order), and
 *       the men on foot take positions around the leader's post
 *       (AIC_fnc_garrisonBuildings with AIC_VEHPOST_INF_RADIUS, no static
 *       weapons) and are settled by AIC_fnc_monitorGarrison like a squad's.
 *       AIC_fnc_classifyGroup still counts the dismounted men as the
 *       vehicle's passengers, so the group stays mechanised.
 *     - done ("garrisonDone") once every vehicle is posted and every man
 *       on foot is placed; a known threat then turns the vehicles to it
 *       when it moves more than 45 degrees ("garrisonWatchDir").
 *   AIC_fnc_dynSimCycle parks such a group only once it is done.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - vehicle group
 *   2: HASHMAP - its group record
 *   3: ARRAY   - (optional) position of the nearest threat, default [] (none)
 *   4: NUMBER  - (optional) the group's sector (bearing), -1 none, default -1
 *   5: BOOL    - (optional) hold the pathfinding of placed men
 *                (AIC_fnc_monitorGarrison), default true
 *
 * Returns:
 *   BOOL - true when the group is settled
 *
 * Example:
 *   [_cmd, _group, _rec, _threatPos] call AIC_fnc_monitorVehiclePosts;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_rec", createHashMap, [createHashMap]],
    ["_threatPos", [], [[]]],
    ["_sector", -1, [0]],
    ["_holdPath", true, [true]]
];

if (isNull _group || {count _rec == 0}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};
private _hasThreat = count _threatPos >= 2;

private _token = _group getVariable ["AIC_orderToken", 0];
if ((_rec getOrDefault ["garrisonToken", -1]) isNotEqualTo _token) then {
    _rec set ["garrisonToken", _token];
    _rec set ["garrisonTime", time];
    _rec set ["garrisonDone", false];
    _rec deleteAt "vehInfPlaced";
    _rec deleteAt "vehDismountTime";
};
private _age = time - (_rec getOrDefault ["garrisonTime", time]);

// the vehicles of the group with a post
private _leaderVeh = objectParent _leader;
private _vehicles = [];
{
    private _v = objectParent _x;
    if (alive _x && {!isNull _v} && {alive _v} && {(_v getVariable ["AIC_vehPost", []]) isNotEqualTo []} && {!(_v in _vehicles)}) then {
        _vehicles pushBack _v;
    };
    // a dismounted man's vehicle still counts
    private _dm = _x getVariable ["AIC_dismounted", objNull];
    if (alive _x && {!isNull _dm} && {alive _dm} && {(_dm getVariable ["AIC_vehPost", []]) isNotEqualTo []} && {!(_dm in _vehicles)}) then {
        _vehicles pushBack _dm;
    };
} forEach (units _group);

// --- done: follow the threat round --------------------------------------------------------
if ((_rec getOrDefault ["garrisonDone", false]) isEqualTo true) exitWith {
    // a vehicle let go (an engagement, a handover) that drifted off its post
    // is sent back once the group is calm, the watcher with it
    if ((time - (_rec getOrDefault ["lastEngaged", -1e6])) > AIC_PATH_CALM) then {
        private _back = _vehicles select {
            _x isNotEqualTo _leaderVeh && {!(_x getVariable ["AIC_vehHeld", false])}
            && {(_x distance2D ((_x getVariable "AIC_vehPost") select 0)) > (3 * AIC_VEHPOST_HOLD)}
        };
        if (_back isNotEqualTo []) then {
            {
                // (the vehicle kept apart: the select below sets _x to each man)
                private _v = _x;
                _v setVariable ["AIC_vehPosted", false];
                _v setVariable ["AIC_vehPostRetry", nil];
                [(crew _v) select {alive _x && {(group _x) isEqualTo _group} && {!isPlayer _x}}, "doStop"] call AIC_fnc_do;
                [_v, "doMove", (_v getVariable "AIC_vehPost") select 0] call AIC_fnc_do;
            } forEach _back;
            _rec set ["garrisonDone", false];
            _rec set ["garrisonTime", time];
            _group setVariable ["AIC_vehWatch", true];
            [_group, _token] spawn AIC_fnc_vehiclePostWatch;
        };
    };
    // the leader took over a held vehicle (his own was lost): its driver drives again
    if (!isNull _leaderVeh && {_leaderVeh getVariable ["AIC_vehHeld", false]}) then {
        [_leaderVeh, _group] call AIC_fnc_releaseVehicle;
    };
    if (_hasThreat) then {
        private _dir = (getPosATL _leader) getDir _threatPos;
        private _old = _rec getOrDefault ["garrisonWatchDir", -1];
        if (_old < 0 || {(abs ((_dir - _old + 540) % 360 - 180)) > 45}) then {
            _rec set ["garrisonWatchDir", _dir];
            {[_x, "doWatch", _threatPos] call AIC_fnc_do} forEach _vehicles;
        };
    };
    true
};

// --- the vehicles: stop each at its post ---------------------------------------------------
private _moving = 0;
{
    private _v = _x;
    if (_v getVariable ["AIC_vehPosted", false]) then {continue};
    (_v getVariable "AIC_vehPost") params ["_p", "_dir"];
    private _d = _v distance2D _p;
    private _spd = speed _v;
    // at its post: on the spot and slowing down (a car driving through at
    // speed is not there yet), or halted within 3 x the post radius of it
    private _there = (_d < AIC_VEHPOST_NEAR && {_spd < 8}) || {_d < (3 * AIC_VEHPOST_NEAR) && {_spd < 0.5}};
    private _stopped = _spd < 0.5;
    private _retried = _v getVariable ["AIC_vehPostRetry", false];
    if (!_there && {_stopped} && {_age > 30} && {!_retried} && {_age < AIC_VEHPOST_TIMEOUT}) then {
        // stopped short (a blocked lane, a move the driver gave up on): once
        // more, out of the formation (doStop) so the leader's hold does not pull it back
        _v setVariable ["AIC_vehPostRetry", true];
        if (_v isNotEqualTo _leaderVeh) then {
            [(crew _v) select {alive _x && {(group _x) isEqualTo _group} && {!isPlayer _x}}, "doStop"] call AIC_fnc_do;
        };
        [_v, "doMove", _p] call AIC_fnc_do;
        _moving = _moving + 1;
        continue;
    };
    if (_there || {_stopped && {_retried} && {_age > 90}} || {_age > AIC_VEHPOST_TIMEOUT}) then {
        // the leader's vehicle holds by its waypoint; the others' crews are
        // stopped (doStop takes men) and the driver's movement switched off,
        // so the vehicle neither circles round the spot its move ended at
        // nor drifts back into formation (AIC_fnc_vehiclePostWatch does the
        // same the second a vehicle reaches its post; AIC_fnc_clearWaypoints
        // and AIC_fnc_garrisonPath let it go)
        if (_v isNotEqualTo _leaderVeh) then {
            [_v, _group] call AIC_fnc_holdVehicle;
        };
        [_v, "doWatch", if (_hasThreat) then {_threatPos} else {_p getPos [300, _dir]}] call AIC_fnc_do;
        if (!_hasThreat) then {[_v, "engineOn", false] call AIC_fnc_do};
        _v setVariable ["AIC_vehPosted", true];
        _v setVariable ["AIC_vehPostRetry", nil];
    } else {
        _moving = _moving + 1;
    };
} forEach _vehicles;
if (_moving > 0) exitWith {false};

// --- the men in cargo get out and take positions round the leader's post --------------------
private _post = if (!isNull _leaderVeh) then {(_leaderVeh getVariable ["AIC_vehPost", [getPosATL _leader]]) select 0} else {getPosATL _leader};
if !("vehDismountTime" in _rec) then {
    private _out = [];
    {
        private _v = objectParent _x;
        if (alive _x && {!isNull _v} && {_v in _vehicles} && {(_v getCargoIndex _x) >= 0} && {!isPlayer _x}) then {
            _x setVariable ["AIC_dismounted", _v];
            _out pushBack _x;
        };
    } forEach (units _group);
    if (_out isNotEqualTo []) then {
        {[_x, "unassignVehicle"] call AIC_fnc_do} forEach _out;
        [_out, "orderGetIn", false] call AIC_fnc_do;
        {[_x, "doGetOut"] call AIC_fnc_do} forEach _out;
        ["garrison: group %1 dismounts %2 men at its post", [groupId _group, count _out]] call AIC_fnc_log;
    };
    _rec set ["vehDismountTime", time];
    _rec set ["garrisonWatchDir", if (_hasThreat) then {(getPosATL _leader) getDir _threatPos} else {-1}];
};
// (they need a moment to climb out; a man still aboard after that is told
// again, for up to AIC_VEHPOST_OUT_MAX s, then he rides along as crew)
private _sinceOut = time - (_rec getOrDefault ["vehDismountTime", time]);
if (_sinceOut < 8) exitWith {false};
private _stillIn = (units _group) select {
    alive _x && {!isNull objectParent _x} && {(objectParent _x) isEqualTo (_x getVariable ["AIC_dismounted", objNull])}
};
if (_stillIn isNotEqualTo []) then {
    if (_sinceOut < AIC_VEHPOST_OUT_MAX) exitWith {
        {[_x, "doGetOut"] call AIC_fnc_do} forEach _stillIn;
    };
    {_x setVariable ["AIC_dismounted", nil]} forEach _stillIn;
};
if (_stillIn isNotEqualTo [] && {_sinceOut < AIC_VEHPOST_OUT_MAX}) exitWith {false};

private _onFoot = (units _group) select {alive _x && {isNull objectParent _x} && {!isPlayer _x}};
if (_onFoot isEqualTo []) exitWith {
    _rec set ["garrisonDone", true];
    true
};
if !((_rec getOrDefault ["vehInfPlaced", false]) isEqualTo true) exitWith {
    // positions once (buildings and cover near the post; no static weapons: the
    // vehicles are the guns here); AIC_fnc_monitorGarrison settles them
    _rec set ["vehInfPlaced", true];
    _rec set ["garrisonTime", time];
    private _sent = [_group, _post, AIC_VEHPOST_INF_RADIUS, _threatPos, false, _sector] call AIC_fnc_garrisonBuildings;
    if (_sent == 0) then {_rec set ["garrisonDone", true]};
    _sent == 0
};
[_group, _rec, _post, AIC_VEHPOST_INF_RADIUS, _threatPos, false, _sector, _holdPath] call AIC_fnc_monitorGarrison
