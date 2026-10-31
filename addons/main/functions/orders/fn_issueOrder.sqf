/*
 * Name: AIC_fnc_issueOrder
 * Description:
 *   Central order dispatcher. Gives a group under a commander a task,
 *   creates the matching waypoints through the order functions and
 *   updates the group record in the commander's "groupData"
 *   ("task", "taskPos", "taskTime", "objective", plus the stuck-detection
 *   keys "lastPos" / "lastMoveTime").
 *   The order is skipped when the same task for the same objective is
 *   already active (for orders without objective: same task and taskPos
 *   within 400 m for ATTACK/REINFORCE, 50 m for the other tasks), unless
 *   _force is true.
 *   Task -> function:
 *     "ATTACK"    -> AIC_fnc_orderAttack    (radius = objective radius)
 *     "DEFEND"    -> AIC_fnc_orderDefend    (radius = objective radius, max 200)
 *     "PATROL"    -> AIC_fnc_orderPatrol    (radius = objective radius, or
 *                                            setting "objectiveRadius")
 *     "RETREAT"   -> AIC_fnc_orderRetreat   (empty pos -> commander "hq")
 *     "REINFORCE" -> AIC_fnc_orderReinforce
 *     "SUPPORT"   -> air: SAD over pos then LOITER near HQ;
 *                    ground: AIC_fnc_orderReinforce
 *     "RTB"       -> AIC_fnc_orderRetreat (a transport going home after a
 *                    drop; empty pos -> its "home" objective, then "hq")
 *     "IDLE"      -> clears waypoints, group holds in place
 *     "TRANSPORT" / "TRANSPORTED" -> only with force: re-runs
 *                    AIC_fnc_orderTransport for the pair stored in the
 *                    record ("transport" partner, cargo "final" order)
 *   Empty/invalid position falls back to: objective position, then (for
 *   RTB) the group's "home" objective, then (for RETREAT/DEFEND/RTB) the
 *   HQ, then the leader's position.
 *
 *   Logistics:
 *     - Groups whose current task is "TRANSPORT" or "TRANSPORTED" are
 *       managed by AIC_fnc_transportCycle: any order to them is skipped
 *       unless _force is true. A forced order ends the pairing (cargo units
 *       leave the transport vehicle, a transport's helipads are deleted,
 *       "transport" / "final" are cleared).
 *     - Before dispatching, the group is woken (AIC_fnc_setGroupSim false).
 *       Skipped (identical) orders do not wake it, so parked garrisons
 *       that keep their order stay parked.
 *     - A group whose members mostly sit in a vehicle driven by another
 *       commanded group (a squad placed in a helicopter, split off by
 *       AIC_fnc_splitPassengers): a far ATTACK / REINFORCE / DEFEND order
 *       becomes a ride with that very vehicle (AIC_fnc_orderTransport, the
 *       ride starts in the vehicle), any other order dismounts the group
 *       (AIC_fnc_dismountCarrier, repeated by AIC_fnc_monitorOrders).
 *     - INF groups ordered to ATTACK / REINFORCE / DEFEND farther than
 *       "transportMinDistance" (setting "useTransport" on, group not
 *       already TRANSPORTED, at least half of it on foot, no ride aborted
 *       for it in the last 600 s - record "rideAbortTime") look for a ride
 *       with AIC_fnc_findTransport. If AIC_fnc_orderTransport succeeds the
 *       function returns true without dispatching: the record now holds
 *       task "TRANSPORTED" (taskPos = target, objective = objective id,
 *       "final" = this order), so the same plan entry next cycle is
 *       skipped as externally managed.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - group to order
 *   2: STRING  - task
 *   3: ARRAY   - target position ([] allowed, see above)
 *   4: STRING  - (optional) objective id, default ""
 *   5: BOOL    - (optional) force re-issue even if identical, default false
 *
 * Returns:
 *   BOOL - true if the order was issued (also when it became a transport
 *          ride), false if skipped/invalid
 *
 * Example:
 *   [_cmd, _grp, "ATTACK", _obj get "pos", _obj get "id"] call AIC_fnc_issueOrder;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_task", "", [""]],
    ["_pos", [], [[]]],
    ["_objective", "", [""]],
    ["_force", false, [false]]
];

if (!isServer) exitWith {false};
if (count _cmd == 0 || {isNull _group} || {_task isEqualTo ""}) exitWith {false};
if (({alive _x} count units _group) == 0) exitWith {false};

_task = toUpperANSI _task;
if !(_task in ["IDLE", "ATTACK", "DEFEND", "PATROL", "RETREAT", "REINFORCE", "SUPPORT", "RTB", "TRANSPORT", "TRANSPORTED"]) exitWith {
    ["issueOrder: unknown task '%1' for group %2", [_task, groupId _group]] call AIC_fnc_log;
    false
};

// --- Group record ------------------------------------------------------------
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then {
    _groupData = createHashMap;
    _cmd set ["groupData", _groupData];
};
private _key = hashValue _group;
private _record = _groupData getOrDefault [_key, createHashMap];
if (count _record == 0) then {
    // Not registered yet (should be rare) - create a complete record
    _record = [_group] call AIC_fnc_newGroupRecord;
    _groupData set [_key, _record];
};
private _type = _record getOrDefault ["type", ""];
if !(_type isEqualType "") then { _type = ""; };
if (_type isEqualTo "") then {
    _type = [_group] call AIC_fnc_classifyGroup;
    _record set ["type", _type];
};

// --- Externally managed: transport rides --------------------------------------
private _curTask = _record getOrDefault ["task", "IDLE"];
if !(_curTask isEqualType "") then { _curTask = "IDLE"; };
if (!_force && {_curTask in ["TRANSPORT", "TRANSPORTED"]}) exitWith {
    if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
        ["issueOrder: group %1 is %2, order %3 skipped (transport system owns it)", [groupId _group, _curTask, _task]] call AIC_fnc_log;
    };
    false
};

// --- Objective lookup --------------------------------------------------------
private _objRec = createHashMap;
if (_objective isNotEqualTo "") then {
    _objRec = [_cmd, _objective] call AIC_fnc_getObjective;
};
private _defRadius = [_cmd, "objectiveRadius"] call AIC_fnc_getSetting;
private _radius = _objRec getOrDefault ["radius", _defRadius];
if !(_radius isEqualType 0) then { _radius = _defRadius; };

// --- Resolve target position --------------------------------------------------
private _hq = _cmd getOrDefault ["hq", []];
if (!(_hq isEqualType []) || {count _hq < 2}) then { _hq = []; };
private _fnc_validPos = {
    params [["_p", []]];
    _p isEqualType [] && {count _p >= 2} && {(_p select 0) isEqualType 0} && {(_p select 1) isEqualType 0}
};

if !([_pos] call _fnc_validPos) then {
    private _objPos = _objRec getOrDefault ["pos", []];
    private _homePos = [];
    if (_task == "RTB") then {
        private _home = _record getOrDefault ["home", ""];
        if (_home isEqualType "" && {_home isNotEqualTo ""}) then {
            _homePos = ([_cmd, _home] call AIC_fnc_getObjective) getOrDefault ["pos", []];
        };
    };
    _pos = switch (true) do {
        case ([_objPos] call _fnc_validPos): {_objPos};
        case ([_homePos] call _fnc_validPos): {_homePos};
        case (_task in ["RETREAT", "DEFEND", "RTB"] && {[_hq] call _fnc_validPos}): {_hq};
        default {getPosATL (leader _group)};
    };
};
_pos = [_pos select 0, _pos select 1, 0];

// --- Forced re-run of a transport ride ----------------------------------------
if (_task in ["TRANSPORT", "TRANSPORTED"]) exitWith {
    private _r = call {
        private _partner = _record getOrDefault ["transport", grpNull];
        if (!(_partner isEqualType grpNull) || {isNull _partner}) exitWith {
            ["issueOrder: %1 for group %2 needs a transport partner, none recorded", [_task, groupId _group]] call AIC_fnc_log;
            false
        };
        private _tGrp = if (_task == "TRANSPORT") then {_group} else {_partner};
        private _cGrp = if (_task == "TRANSPORT") then {_partner} else {_group};
        private _cRec = _groupData getOrDefault [hashValue _cGrp, createHashMap];
        private _final = _cRec getOrDefault ["final", createHashMap];
        if (!(_final isEqualType createHashMap) || {count _final == 0}) exitWith {
            ["issueOrder: %1 for group %2: cargo %3 has no final order", [_task, groupId _group, groupId _cGrp]] call AIC_fnc_log;
            false
        };
        private _fPos = _final getOrDefault ["pos", []];
        if !([_fPos] call _fnc_validPos) then { _fPos = _pos; };
        private _fTask = _final getOrDefault ["task", "DEFEND"];
        if !(_fTask isEqualType "") then { _fTask = "DEFEND"; };
        private _fObj = _final getOrDefault ["objective", ""];
        if !(_fObj isEqualType "") then { _fObj = ""; };
        [_cmd, _tGrp, _cGrp, _fPos, _fTask, _fPos, _fObj] call AIC_fnc_orderTransport
    };
    if (isNil "_r" || {!(_r isEqualType true)}) then { _r = false; };
    _r
};

// --- Skip identical active orders --------------------------------------------
private _curObj = _record getOrDefault ["objective", ""];
private _curPos = _record getOrDefault ["taskPos", []];
if (!_force && {_curTask == _task}) then {
    private _same = if (_objective isNotEqualTo "") then {
        _curObj == _objective
    } else {
        // Objective-less orders: ATTACK/REINFORCE targets (e.g. counter-attacks
        // on a drifting threat-cluster centre) count as the same job within
        // 400 m - the same tolerance AIC_fnc_allocateForces uses. Fixed
        // points (HQ DEFEND/PATROL/RETREAT, SUPPORT) use 50 m.
        private _tol = if (_task in ["ATTACK", "REINFORCE"]) then {AIC_REISSUE_TOL_MOVING} else {AIC_REISSUE_TOL_FIXED};
        _curObj isEqualTo "" && {[_curPos] call _fnc_validPos} && {(_curPos distance2D _pos) < _tol}
    };
    if (_same) then { _task = "" };
};
if (_task isEqualTo "") exitWith {false};

// --- Wake the group (parked by dynamic simulation) ----------------------------
[_cmd, _group, false] call AIC_fnc_setGroupSim;

// --- A forced order ends a transport pairing ----------------------------------
if (_curTask isEqualTo "TRANSPORTED") then {
    private _veh = _record getOrDefault ["transportVeh", objNull];
    // (a flying helicopter lands first, AIC_fnc_transportCycle then gets them out)
    if (_veh isEqualType objNull && {!isNull _veh}
        && {!(_veh isKindOf "Air") || {[_veh] call AIC_fnc_isLanded} || {!alive (driver _veh)}}) then {
        {
            if (alive _x && {objectParent _x isEqualTo _veh}) then {
                unassignVehicle _x;
                [_x] orderGetIn false;
                doGetOut _x;
            };
        } forEach (units _group);
        _group leaveVehicle _veh;
    };
    _record set ["transport", grpNull];
    _record set ["final", createHashMap];
    _record set ["transportPhase", ""];
};
if (_curTask isEqualTo "TRANSPORT") then {
    [_record] call AIC_fnc_deleteHelipads;
    private _veh = _record getOrDefault ["transportVeh", objNull];
    if (_veh isEqualType objNull && {!isNull _veh} && {alive _veh} && {_veh isKindOf "Air"}) then { _veh land "NONE"; };
    _record set ["transport", grpNull];
};

// --- Aboard another commanded group's vehicle ---------------------------------
// (a squad placed in a helicopter / truck, split off by AIC_fnc_splitPassengers)
private _rideAbort = _record getOrDefault ["rideAbortTime", -1e6];
if !(_rideAbort isEqualType 0) then { _rideAbort = -1e6; };
if (_curTask isNotEqualTo "TRANSPORTED") then {
    private _alive = (units _group) select {alive _x};
    private _carrier = objNull;
    private _aboard = 0;
    {
        private _v = objectParent _x;
        if (!isNull _v) then {
            private _n = { objectParent _x isEqualTo _v } count _alive;
            if (_n > _aboard) then { _aboard = _n; _carrier = _v; };
        };
    } forEach _alive;
    if (!isNull _carrier && { (_aboard * 2) >= count _alive }) then {
        private _drv = driver _carrier;
        private _cGrp = if (isNull _drv) then { grpNull } else { group _drv };
        private _cRec = if (isNull _cGrp) then { createHashMap } else { _groupData getOrDefault [hashValue _cGrp, createHashMap] };
        if (!(_cGrp isEqualTo _group) && { count _cRec > 0 } && { alive _drv }) then {
            private _far = ((getPosATL (leader _group)) distance2D _pos) > ([_cmd, "transportMinDistance"] call AIC_fnc_getSetting);
            private _rideOk = _task in ["ATTACK", "REINFORCE", "DEFEND"] && { _far }
                && { ([_cmd, "useTransport"] call AIC_fnc_getSetting) isEqualTo true }
                && { (time - _rideAbort) >= AIC_RIDE_ABORT_COOLDOWN }
                && { (_cRec getOrDefault ["type", ""]) in ["MOTOR", "MECH", "HELI"] }
                && { (_cRec getOrDefault ["task", "IDLE"]) in ["IDLE", "DEFEND", "PATROL"] }
                && { canMove _carrier };
            if (_rideOk) then {
                _cGrp setVariable ["AIC_transportVehicle", _carrier];
                private _r = [_cmd, _cGrp, _group, _pos, _task, _pos, _objective] call AIC_fnc_orderTransport;
                if (!isNil "_r" && {_r isEqualTo true}) then { _task = "TRANSPORTED"; };
            };
            if (_task isNotEqualTo "TRANSPORTED") then {
                // no ride: get out (AIC_fnc_monitorOrders repeats this until they are out)
                [_group, _carrier, (_cRec getOrDefault ["task", ""]) isNotEqualTo "TRANSPORT"] call AIC_fnc_dismountCarrier;
            };
        };
    };
};

// --- Long infantry moves: try to get a ride -----------------------------------
// (no new ride within 600 s of an aborted one: "rideAbortTime" is set by
// AIC_fnc_transportCycle, so a failing vehicle cannot cause abort/re-ride loops)
if (_type == "INF" && {_task in ["ATTACK", "REINFORCE", "DEFEND"]} && {_curTask isNotEqualTo "TRANSPORTED"}
    && {(time - _rideAbort) >= AIC_RIDE_ABORT_COOLDOWN}
    && {([_cmd, "useTransport"] call AIC_fnc_getSetting) isEqualTo true}) then {
    private _minDist = [_cmd, "transportMinDistance"] call AIC_fnc_getSetting;
    private _alive = (units _group) select {alive _x};
    private _mounted = {!isNull objectParent _x} count _alive;
    if (_alive isNotEqualTo [] && {(_mounted * 2) <= count _alive}
        && {((getPosATL (leader _group)) distance2D _pos) > _minDist}) then {
        private _tGrp = [_cmd, _group, _pos] call AIC_fnc_findTransport;
        if (!isNil "_tGrp" && {_tGrp isEqualType grpNull} && {!isNull _tGrp}) then {
            private _r = [_cmd, _tGrp, _group, _pos, _task, _pos, _objective] call AIC_fnc_orderTransport;
            if (!isNil "_r" && {_r isEqualTo true}) then { _task = "TRANSPORTED"; };
        };
    };
};
if (_task isEqualTo "TRANSPORTED") exitWith {
    ["%1: group %2 rides with %3 to %4 obj '%5'", [
        _cmd getOrDefault ["side", sideUnknown], groupId _group,
        groupId (_record getOrDefault ["transport", grpNull]), _pos apply {round _x}, _objective
    ]] call AIC_fnc_log;
    true
};

// --- Dispatch ----------------------------------------------------------------
private _ok = switch (_task) do {
    case "ATTACK":    { [_group, _pos, _radius, _type] call AIC_fnc_orderAttack };
    case "DEFEND": {
        // trucks wait behind the town instead of on the threatened side
        private _rear = (_record getOrDefault ["transportOnly", false]) isEqualTo true;
        private _threatPos = [_cmd, _pos] call AIC_fnc_nearestThreat;
        [_group, _pos, [_radius min 200, 60] select _rear, _type, _threatPos, _rear] call AIC_fnc_orderDefend
    };
    case "PATROL":    { [_group, _pos, _radius, _type] call AIC_fnc_orderPatrol };
    case "RETREAT":   { [_group, _pos, _type] call AIC_fnc_orderRetreat };
    case "RTB":       { [_group, _pos, _type] call AIC_fnc_orderRetreat };
    case "REINFORCE": { [_group, _pos, _type] call AIC_fnc_orderReinforce };
    case "SUPPORT": {
        if (_type in ["HELI", "PLANE"]) then {
            private _r = [_group, _pos, 200, _type] call AIC_fnc_orderAttack;
            if (_r) then {
                private _home = if ([_hq] call _fnc_validPos) then {[_hq select 0, _hq select 1, 0]} else {getPosATL (leader _group)};
                private _wpL = _group addWaypoint [_home, 0];
                _wpL setWaypointType "LOITER";
                _wpL setWaypointLoiterType "CIRCLE_L";
                _wpL setWaypointLoiterRadius (if (_type == "PLANE") then {1200} else {400});
                _wpL setWaypointBehaviour "AWARE";
                _wpL setWaypointCombatMode "YELLOW";
                _wpL setWaypointSpeed "NORMAL";
                // AIC_fnc_supportCycle treats the group as free again once it reaches this waypoint
                _group setVariable ["AIC_airLoiterWp", _wpL select 1];
            };
            _r
        } else {
            [_group, _pos, _type] call AIC_fnc_orderReinforce
        };
    };
    case "IDLE": {
        [_group] call AIC_fnc_clearWaypoints;
        true
    };
    default {false};
};
if (isNil "_ok") then { _ok = false; };

// Static/arty groups return false from movement orders but still hold the
// task (they fight in place), so the record is updated regardless.
_record set ["task", _task];
_record set ["taskPos", if (_task == "IDLE") then {[]} else {_pos}];
_record set ["taskTime", time];
_record set ["objective", if (_task == "IDLE") then {""} else {_objective}];
_record set ["lastPos", getPosATL (leader _group)];
_record set ["lastMoveTime", time];
// a new order starts building occupation over (AIC_fnc_monitorGarrison)
_record set ["garrisonToken", -1];
_record set ["garrisonDone", false];

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["%1: group %2 (%3) -> %4 %5 obj '%6'%7", [
        _cmd getOrDefault ["side", sideUnknown], groupId _group, _type, _task,
        _pos apply {round _x}, _objective, if (_force) then {" (forced)"} else {""}
    ]] call AIC_fnc_log;
};

true
