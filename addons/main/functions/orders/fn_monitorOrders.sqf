/*
 * Name: AIC_fnc_monitorOrders
 * Description:
 *   Follows up on the orders of every group under a commander.
 *   Completion (task -> "IDLE", taskPos [], objective ""):
 *     ATTACK (objective) : the objective's "owner" is the commander's side
 *                          and the leader arrived (or waypoints done).
 *                          While uncaptured the task is kept; once all its
 *                          waypoints are done, the leader is within the
 *                          arrival radius and the task is older than
 *                          600 s, the order is re-issued with force
 *                          (re-sweep).
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
 *                          1500 m after 60 s. A helicopter finishing RTB or
 *                          RETREAT is told to land, so the dynamic-simulation
 *                          system can park it. A helicopter airborne and IDLE
 *                          for 180 s (a finished CAS job) gets RTB to its
 *                          place in the nearest base's helicopter park.
 *     SUPPORT            : after 10 min (air sorties end in a loiter).
 *     PATROL / DEFEND    : standing orders, never auto-complete. An awake
 *                          INF group on DEFEND occupies buildings through
 *                          AIC_fnc_monitorGarrison (one step per cycle).
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
 *   within 400 m, engaged in the last 120 s - record "lastEngaged" - or
 *   leader in COMBAT behaviour), STATIC/ARTY/PLANE groups and groups whose
 *   leader vehicle cannot move are not treated as stuck.
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

private _changes = 0;
private _reissue = [];
private _attackSplits = [];
private _goHome = [];

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

    // a helicopter with nothing to do goes to a base, it does not hang in the air
    if (_task == "IDLE" && {_type == "HELI"} && {(time - _taskTime) > 180}) then {
        private _air = objectParent _leader;
        if (!isNull _air && {_air isKindOf "Helicopter"} && {!isTouchingGround _air}) then {_goHome pushBack _group};
    };

    if (_task == "IDLE" || {!(_taskPos isEqualType [])} || {count _taskPos < 2}) then { continue };
    // transport rides are followed by AIC_fnc_transportCycle
    if (_task in ["TRANSPORT", "TRANSPORTED"]) then { continue };

    // a squad on orders that still sits in another group's vehicle (the
    // vehicle was moving when the order came) keeps trying to get out
    private _carrier = objectParent _leader;
    if (_type == "INF" && {!isNull _carrier} && {!(_carrier isKindOf "StaticWeapon")}) then {
        private _drv = driver _carrier;
        if (alive _drv && {!isPlayer _drv} && {(group _drv) isNotEqualTo _group}) then {
            private _cRec = _groupData getOrDefault [hashValue (group _drv), createHashMap];
            [_group, _carrier, (_cRec getOrDefault ["task", ""]) isNotEqualTo "TRANSPORT"] call AIC_fnc_dismountCarrier;
        };
    };

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

    // --- infantry DEFEND: occupy buildings once arrived (unscheduled, one
    // step per cycle; AIC_fnc_dynSimCycle parks the group only when done).
    // Same radius as AIC_fnc_issueOrder gives AIC_fnc_orderDefend.
    if (_task == "DEFEND" && {_type == "INF"}) then {
        [
            _group, _rec, _taskPos, (_objRec getOrDefault ["radius", _defRadius]) min 200,
            [_cmd, _taskPos] call AIC_fnc_nearestThreat,
            ([_cmd, "garrisonManStatics"] call AIC_fnc_getSetting) isEqualTo true
        ] call AIC_fnc_monitorGarrison;
    };

    // --- completion -----------------------------------------------------------
    private _done = switch (_task) do {
        case "ATTACK";
        case "REINFORCE": {
            if (_task == "ATTACK" && {count _objRec > 0}) then {
                // ATTACK on a known objective: only finished once the
                // objective is actually ours (updateObjectives 2:1 rule).
                // Until then the task/objective stay, so issueOrder's
                // same-objective skip keeps the group from being re-ordered.
                ((_objRec getOrDefault ["owner", sideUnknown]) isEqualTo _side)
                && {_dist < _arriveR || {_wpDone} || {(_rec getOrDefault ["overwatch", false]) isEqualTo true}}
                && {_age > 30}
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
            private _lv = objectParent _leader;
            // a transport whose vehicle is wrecked/immobile never gets home:
            // end RTB so the garrison system can take the crew over
            if (_task == "RTB" && {!isNull _lv} && {!alive _lv || {!canMove _lv}}) then { true } else {
                switch (_type) do {
                    // planes end the retreat in a 1200 m LOITER and never stop
                    case "PLANE": { _dist < AIC_NEAR_HQ_PLANE && {_age > 60} };
                    // helicopters HOLD/hover above the rally point; a transport
                    // going back to its parking place (RTB) lands there, not
                    // on the nearest helipad 300 m away
                    case "HELI": { _dist < ([300, 120] select (_task == "RTB")) && {_age > 30} };
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
        if (_task in ["RTB", "RETREAT"] && {_type == "HELI"}) then {
            private _veh = objectParent _leader;
            if (!isNull _veh && {alive _veh} && {_veh isKindOf "Helicopter"} && {!isTouchingGround _veh}) then {
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

    // --- a big squad nearing its target splits into fireteams (after this
    // loop: AIC_fnc_splitForAttack adds records to groupData)
    if (_task == "ATTACK" && {_type == "INF"}
        && {!((_rec getOrDefault ["staged", false]) isEqualTo true)}
        && {!((_rec getOrDefault ["overwatch", false]) isEqualTo true)}
        && {_dist < AIC_ATTACK_SPLIT_RANGE} && {_dist > 200}
        && {(time - (_rec getOrDefault ["lastSplit", -1e6])) > AIC_ATTACK_SPLIT_COOLDOWN}
        && {({alive _x} count (units _group)) >= AIC_ATTACK_SPLIT_SIZE}) then {
        _attackSplits pushBack [_group, _rec, +_taskPos, _objId];
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
    // waiting in an assembly area (once there) or on overwatch is the order,
    // not being stuck; a group still on its way to the assembly area is checked
    if (_task == "ATTACK" && {
        (_rec getOrDefault ["overwatch", false]) isEqualTo true
        || {(_rec getOrDefault ["staged", false]) isEqualTo true
            && {count (_rec getOrDefault ["stagePos", []]) >= 2}
            && {(_leaderPos distance2D (_rec get "stagePos")) < 150}}
    }) then { continue };
    if !(_task in ["ATTACK", "REINFORCE", "RETREAT", "RTB", "PATROL", "DEFEND", "SUPPORT"]) then { continue };
    if (time - _lastMoveTime < AIC_STUCK_TIMEOUT) then { continue };

    // a group marching to its assembly area is measured against that, not the town
    if (_task == "ATTACK" && {(_rec getOrDefault ["staged", false]) isEqualTo true}
        && {count (_rec getOrDefault ["stagePos", []]) >= 2}) then {
        _dist = _leaderPos distance2D (_rec get "stagePos");
    };
    // DEFEND: AIC_fnc_orderDefend holds vehicle groups up to ~260 m from the
    // centre (100 m offset + 120 m road snap + 40 m completion radius), so a
    // group holding there is not stuck
    private _far = switch (_task) do {
        case "PATROL": { true };
        case "DEFEND": { _dist > ((_arriveR max 200) + 100) };
        default { _dist > (_arriveR max 200) };
    };
    if (!_far) then { continue };

    // In contact: standing still is fighting, not being stuck. Besides a
    // close enemy, a recent engagement (event handlers stamp "lastEngaged")
    // or COMBAT behaviour count, so a group pinned by a distant contact is
    // not re-ordered (PATROL: new random route) in the middle of a fight.
    private _enemy = _leader findNearestEnemy _leader;
    private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
    if (
        (!isNull _enemy && {(_enemy distance2D _leader) < 400})
        || {_engaged isEqualType 0 && {(time - _engaged) < 120}}
        || {behaviour _leader == "COMBAT"}
    ) then {
        _rec set ["lastMoveTime", time];
        continue;
    };

    private _veh = objectParent _leader;
    if (!isNull _veh && {!canMove _veh}) then { continue };

    _reissue pushBack [_group, _task, +_taskPos, _objId, _rec];
} forEach _groupData;

{
    _x params ["_group", "_rec", "_taskPos", "_objId"];
    if ([_cmd, _group, _rec, _taskPos, _objId] call AIC_fnc_splitForAttack) then {
        _changes = _changes + 1;
    };
} forEach _attackSplits;

{
    private _base = [_cmd, getPosATL (leader _x)] call AIC_fnc_nearestBase;
    private _slot = [_cmd, _x, [_cmd, _base] call AIC_fnc_getObjective, true] call AIC_fnc_parkSlot;
    [_cmd, _x, "RTB", _slot, "", true] call AIC_fnc_issueOrder;
    _changes = _changes + 1;
} forEach _goHome;

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
