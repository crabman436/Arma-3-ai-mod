/*
 * Name: AIC_fnc_monitorOrders
 * Description:
 *   Follows up on the orders of every group under a commander.
 *   Completion (task -> "IDLE", taskPos [], objective ""):
 *     ATTACK (objective) : the objective's "owner" is the commander's side
 *                          and the leader arrived (or waypoints done).
 *                          While uncaptured the task is kept; if the SAD is
 *                          finished on the objective for > 600 s the order
 *                          is re-issued with force (re-sweep).
 *     ATTACK (no obj.) /
 *     REINFORCE          : leader within arrival radius of taskPos and
 *                          (all waypoints done OR no known enemy contact
 *                          near the target), or older than 20 min with all
 *                          waypoints done.
 *     RETREAT / RTB      : ground: leader within 220 m of taskPos and
 *                          waypoints done or the group has stopped;
 *                          RTB also ends at once if the leader's vehicle
 *                          cannot move any more;
 *                          HELI: within 300 m after 30 s; PLANE: within
 *                          1500 m after 60 s. A helicopter finishing RTB
 *                          (a transport back home) is told to land, so
 *                          the dynamic-simulation system can park it.
 *     SUPPORT            : after 10 min (air sorties end in a loiter).
 *     PATROL / DEFEND    : standing orders, never auto-complete.
 *     TRANSPORT /
 *     TRANSPORTED        : skipped entirely - AIC_fnc_transportCycle owns
 *                          transport rides (only the movement bookkeeping
 *                          below is refreshed).
 *   Stuck detection (group record keys "lastPos" / "lastMoveTime"): the
 *   record remembers the leader position whenever the group moved more
 *   than 20 m. If a moving task (ATTACK, REINFORCE, RETREAT, RTB, PATROL,
 *   DEFEND, SUPPORT) has not moved for 180 s while the leader is still far
 *   from taskPos (PATROL: regardless of distance), the order is re-issued
 *   with force through AIC_fnc_issueOrder. Parked groups (dynamic
 *   simulation enabled) are never treated as stuck. Groups in contact (enemy
 *   within 400 m), STATIC/ARTY/PLANE groups and groups whose leader
 *   vehicle cannot move are not treated as stuck.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - number of orders that were completed or re-issued
 *
 * Example:
 *   [_commander] call AIC_fnc_monitorOrders;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if (!(_groupData isEqualType createHashMap) || {count _groupData == 0}) exitWith {0};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _enemies = _cmd getOrDefault ["knownEnemies", []];
if !(_enemies isEqualType []) then { _enemies = []; };
private _defRadius = [_cmd, "objectiveRadius"] call AIC_fnc_getSetting;
if (isNil "_defRadius" || {!(_defRadius isEqualType 0)}) then { _defRadius = 300; };

private _changes = 0;
private _reissue = [];

private _fnc_setIdle = {
    params ["_rec"];
    _rec set ["task", "IDLE"];
    _rec set ["taskPos", []];
    _rec set ["taskTime", time];
    _rec set ["objective", ""];
};

{
    private _rec = _y;
    if !(_rec isEqualType createHashMap) then { continue };
    private _group = _rec getOrDefault ["group", grpNull];
    if (isNull _group) then { continue };
    private _leader = leader _group;
    if (isNull _leader || {!alive _leader}) then { continue };

    private _task = _rec getOrDefault ["task", "IDLE"];
    private _type = _rec getOrDefault ["type", "INF"];
    private _taskPos = _rec getOrDefault ["taskPos", []];
    private _taskTime = _rec getOrDefault ["taskTime", time];
    private _leaderPos = getPosATL _leader;

    // --- movement bookkeeping ---------------------------------------------
    private _lastPos = _rec getOrDefault ["lastPos", []];
    if (!(_lastPos isEqualType []) || {count _lastPos < 2}) then {
        _rec set ["lastPos", _leaderPos];
        _rec set ["lastMoveTime", time];
        _lastPos = _leaderPos;
    };
    if ((_leaderPos distance2D _lastPos) > AIC_MOVE_THRESHOLD) then {
        _rec set ["lastPos", _leaderPos];
        _rec set ["lastMoveTime", time];
    };
    private _lastMoveTime = _rec getOrDefault ["lastMoveTime", time];

    // Parked groups are frozen on purpose: never treat them as stuck
    if (dynamicSimulationEnabled _group || {(_rec getOrDefault ["parked", false]) isEqualTo true}) then {
        _rec set ["lastPos", _leaderPos];
        _rec set ["lastMoveTime", time];
        continue
    };

    if (_task == "IDLE" || {!(_taskPos isEqualType [])} || {count _taskPos < 2}) then { continue };
    // transport rides are followed by AIC_fnc_transportCycle
    if (_task in ["TRANSPORT", "TRANSPORTED"]) then { continue };

    private _dist = _leaderPos distance2D _taskPos;
    private _wps = waypoints _group;
    private _wpDone = (count _wps == 0) || {(currentWaypoint _group) >= count _wps};
    private _age = time - _taskTime;

    // arrival radius from the objective (if any)
    private _objId = _rec getOrDefault ["objective", ""];
    private _radius = 150;
    private _objRec = createHashMap;
    if (_objId isNotEqualTo "") then {
        _objRec = [_cmd, _objId] call AIC_fnc_getObjective;
        if (count _objRec > 0) then {
            _radius = _objRec getOrDefault ["radius", _defRadius];
        };
    };
    private _arriveR = ((_radius * 0.6) max 100) min 300;

    // --- completion -----------------------------------------------------------
    private _done = switch (_task) do {
        case "ATTACK";
        case "REINFORCE": {
            if (_task == "ATTACK" && {count _objRec > 0}) then {
                // ATTACK on a known objective: only finished once the
                // objective is actually ours (updateObjectives 2:1 rule).
                // Until then the task/objective stay, so issueOrder's
                // same-objective skip keeps the group from being re-ordered.
                ((_objRec getOrDefault ["owner", sideUnknown]) isEqualTo _side) && {_dist < _arriveR || {_wpDone}} && {_age > 30}
            } else {
                private _near = _dist < _arriveR;
                private _clear = (_enemies findIf {
                    _x isEqualType createHashMap && {((_x getOrDefault ["pos", [0,0,0]]) distance2D _taskPos) < (_arriveR + 200)}
                }) < 0;
                (_near && {_wpDone || _clear} && {_age > 30}) || {_wpDone && {_age > 1200}}
            };
        };
        case "RETREAT";
        case "RTB": {
            private _lv = vehicle _leader;
            // a transport whose vehicle is wrecked/immobile never gets home:
            // end RTB so the garrison system can take the crew over
            if (_task == "RTB" && {_lv != _leader} && {!alive _lv || {!canMove _lv}}) then { true } else {
                switch (_type) do {
                    // planes end the retreat in a 1200 m LOITER and never stop
                    case "PLANE": { _dist < AIC_NEAR_HQ_PLANE && {_age > 60} };
                    // helicopters HOLD/hover above the rally point
                    case "HELI": { _dist < 300 && {_age > 30} };
                    // vehicles are road-snapped up to 150 m from HQ (+60 m wp radius)
                    default { _dist < 220 && {_wpDone || {(speed vehicle _leader) < 1}} && {_age > 10} };
                };
            };
        };
        case "SUPPORT": { _age > 600 };
        default { false };
    };
    if (_done) then {
        if (_task in ["RETREAT", "RTB"]) then {
            _group setBehaviour "AWARE";
            _group setCombatMode "YELLOW";
            _group setSpeedMode "NORMAL";
        };
        // a transport helicopter back home lands (airborne groups are never parked)
        if (_task == "RTB" && {_type == "HELI"}) then {
            private _veh = vehicle _leader;
            if (_veh != _leader && {alive _veh} && {_veh isKindOf "Helicopter"} && {!isTouchingGround _veh}) then {
                [_group] call AIC_fnc_clearWaypoints;
                _veh land "LAND";
            };
        };
        [_rec] call _fnc_setIdle;
        _changes = _changes + 1;
        if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
            ["%1: group %2 finished %3", [_cmd getOrDefault ["side", sideUnknown], groupId _group, _task]] call AIC_fnc_log;
        };
        continue;
    };

    // --- re-sweep: ATTACK sitting on an uncaptured objective with its SAD
    // finished for a while -> refresh the order (new SAD) with force.
    if (_task == "ATTACK" && {count _objRec > 0} && {_wpDone} && {_age > 600}
        && {_dist < _arriveR} && {!(_type in ["STATIC", "ARTY"])}) then {
        _reissue pushBack [_group, _task, +_taskPos, _objId, _rec];
        continue;
    };

    // --- stuck detection --------------------------------------------------------
    if (_type in ["STATIC", "ARTY", "PLANE"]) then { continue };
    if !(_task in ["ATTACK", "REINFORCE", "RETREAT", "RTB", "PATROL", "DEFEND", "SUPPORT"]) then { continue };
    if (time - _lastMoveTime < AIC_STUCK_TIMEOUT) then { continue };

    private _far = if (_task == "PATROL") then { true } else { _dist > (_arriveR max 200) };
    if (!_far) then { continue };

    // In contact: standing still is fighting, not being stuck
    private _enemy = _leader findNearestEnemy _leader;
    if (!isNull _enemy && {(_enemy distance2D _leader) < 400}) then {
        _rec set ["lastMoveTime", time];
        continue;
    };

    private _veh = vehicle _leader;
    if (_veh != _leader && {!canMove _veh}) then { continue };

    _reissue pushBack [_group, _task, +_taskPos, _objId, _rec];
} forEach _groupData;

// Re-issue outside the iteration (issueOrder may touch groupData)
{
    _x params ["_group", "_task", "_taskPos", "_objId", "_rec"];
    if (!isNull _group) then {
        ["%1: group %2 re-issuing %3 (stuck or re-sweep, last move %4 s ago)", [
            _cmd getOrDefault ["side", sideUnknown], groupId _group, _task,
            round (time - (_rec getOrDefault ["lastMoveTime", time]))
        ]] call AIC_fnc_log;
        [_cmd, _group, _task, _taskPos, _objId, true] call AIC_fnc_issueOrder;
        _rec set ["lastPos", getPosATL (leader _group)];
        _rec set ["lastMoveTime", time];
        _changes = _changes + 1;
    };
} forEach _reissue;

_changes
