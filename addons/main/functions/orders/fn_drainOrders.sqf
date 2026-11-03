/*
 * Name: AIC_fnc_drainOrders
 * Description:
 *   Gives every due order of the commander's "orderQueue" (written by
 *   AIC_fnc_queueOrder) through AIC_fnc_issueOrder, infantry first (as the
 *   plan loop does: a squad asks for a ride before the vehicles next to it
 *   are taken), then by due time. Called by AIC_fnc_commanderCycle at the
 *   start of a cycle (orders that fell due during the sleep) and right
 *   after the plan.
 *   A queued order is dropped (never given) when:
 *     - the group is null, has no living unit or no record (or "removed");
 *     - the group got another order meanwhile that takes it away from the
 *       plan: its record "taskTime" changed since the order was queued and
 *       the new task is RETREAT, RTB, TRANSPORT, TRANSPORTED, RECON or
 *       ATTACK (a forced fall-back, a ride, a recon job, an assault order).
 *       Garrison routine (DEFEND / PATROL / IDLE) does not cancel a plan;
 *     - the group is broken (setting "useMorale", record "brokenUntil"
 *       later than now) and the order would send it anywhere but home
 *       (ATTACK, RECON, REINFORCE, SUPPORT, PATROL);
 *     - the plan changed its mind: the commander's "plan" (the plan the
 *       queue was written from; this runs right after the plan loop and at
 *       the start of the next cycle) has no entry for the group with the
 *       same task and objective (objective-less: position within the
 *       AIC_fnc_issueOrder tolerance). Only the plan loop queues orders, so
 *       a group the planner dropped (a held, capped or released attack, a
 *       garrison leftover) loses its stale order;
 *     - an ATTACK on an objective that has become ours, whose last assault
 *       failed or was called off ("failedUntil" later than now, or the
 *       commander's "adviceAbort" [time, id] younger than
 *       AIC_ADVICE_ABORT_COOLDOWN), or that is held back on Jev advice
 *       ("advice" "hold_reason" set) while no group of ours is on ATTACK
 *       there or riding there (a new attack, not a reinforcement).
 *   An order the group already has is skipped by AIC_fnc_issueOrder's
 *   same-order check (queued orders are never forced: forced orders are
 *   not delayed).
 *   The queue is written back as a new array (and the commander's
 *   "orderQueueIndex" of AIC_fnc_queueOrder deleted), so entries
 *   AIC_fnc_queueOrder emptied in place are gone afterwards.
 *   A delayed ATTACK on an objective that went out is noted in the
 *   commander key "ordersOut" (HashMap objective id -> time) for
 *   AIC_fnc_report ("Attack on X: orders issued").
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   NUMBER - number of orders issued
 *
 * Example:
 *   [_cmd] call AIC_fnc_drainOrders;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};

private _queue = _cmd getOrDefault ["orderQueue", []];
if (!(_queue isEqualType []) || {_queue isEqualTo []}) exitWith {0};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then {_groupData = createHashMap};
private _useMorale = ([_cmd, "useMorale"] call AIC_fnc_getSetting) isEqualTo true;
private _side = _cmd getOrDefault ["side", sideUnknown];

// the plan the queue was written from: hashValue group -> [task, objective, pos]
private _planned = createHashMap;
private _plan = _cmd getOrDefault ["plan", -1];
private _checkPlan = _plan isEqualType [];
if (_checkPlan) then {
    {
        if (_x isEqualType createHashMap) then {
            private _g = _x getOrDefault ["group", grpNull];
            if (_g isEqualType grpNull && {!isNull _g}) then {
                _planned set [hashValue _g, [_x getOrDefault ["task", ""], _x getOrDefault ["objective", ""], _x getOrDefault ["pos", []]]];
            };
        };
    } forEach _plan;
};
private _fnc_inPlan = {
    params ["_hv", "_task", "_pos", "_objective"];
    private _p = _planned getOrDefault [_hv, []];
    if (count _p < 3) exitWith {false};
    _p params ["_pTask", "_pObj", "_pPos"];
    _pTask isEqualTo _task && {_pObj isEqualTo _objective} && {
        _objective isNotEqualTo ""
        || {_pPos isEqualTo _pos}
        || {_pPos isEqualType [] && {count _pPos >= 2} && {_pos isEqualType []} && {count _pos >= 2}
            && {(_pPos distance2D _pos) < ([AIC_REISSUE_TOL_FIXED, AIC_REISSUE_TOL_MOVING] select (_task in ["ATTACK", "REINFORCE"]))}}
    }
};

// attacks that are called off or held: objective id -> true
private _advice = _cmd getOrDefault ["advice", createHashMap];
if !(_advice isEqualType createHashMap) then {_advice = createHashMap};
private _hold = _advice getOrDefault ["hold_reason", ""];
private _holdOn = _hold isEqualType "" && {_hold isNotEqualTo ""};
private _abortId = "";
private _abort = _cmd getOrDefault ["adviceAbort", []];
if (_abort isEqualType [] && {count _abort >= 2} && {(_abort select 0) isEqualType 0}
    && {(time - (_abort select 0)) < AIC_ADVICE_ABORT_COOLDOWN} && {(_abort select 1) isEqualType ""}) then {
    _abortId = _abort select 1;
};
// objectives a group of ours is attacking or riding to (only needed under a hold)
private _fought = createHashMap;
if (_holdOn) then {
    {
        if (_y isEqualType createHashMap) then {
            private _t = _y getOrDefault ["task", ""];
            if (_t isEqualTo "ATTACK") then {_fought set [_y getOrDefault ["objective", ""], true]};
            if (_t isEqualTo "TRANSPORTED") then {
                private _f = _y getOrDefault ["final", createHashMap];
                if (_f isEqualType createHashMap && {(_f getOrDefault ["task", ""]) isEqualTo "ATTACK"}) then {
                    _fought set [_f getOrDefault ["objective", ""], true];
                };
            };
        };
    } forEach _groupData;
};
private _fnc_attackOff = {
    params ["_objective"];
    if (_objective isEqualTo "") exitWith {false};
    if (_objective isEqualTo _abortId) exitWith {true};
    private _obj = [_cmd, _objective] call AIC_fnc_getObjective;
    if (count _obj == 0) exitWith {true};
    if ((_obj getOrDefault ["owner", sideUnknown]) isEqualTo _side) exitWith {true};
    private _until = _obj getOrDefault ["failedUntil", -1];
    if (_until isEqualType 0 && {_until > time}) exitWith {true};
    _holdOn && {!(_objective in _fought)}
};

private _keep = [];
private _due = [];   // [infantry 0 / other 1, dueTime, index into _queue]
{
    _x params [["_dueTime", 0, [0]], ["_group", grpNull, [grpNull]], ["_task", "", [""]], ["_qPos", [], [[]]], ["_qObj", "", [""]], "", ["_stamp", -1, [0]]];
    if (isNull _group || {({alive _x} count (units _group)) == 0}) then {continue};
    if (_checkPlan && {!([hashValue _group, _task, _qPos, _qObj] call _fnc_inPlan)}) then {continue};
    if (_task isEqualTo "ATTACK" && {[_qObj] call _fnc_attackOff}) then {continue};
    private _rec = _groupData getOrDefault [hashValue _group, createHashMap];
    if (count _rec == 0 || {(_rec getOrDefault ["removed", false]) isEqualTo true}) then {continue};

    private _curTask = _rec getOrDefault ["task", "IDLE"];
    private _taskTime = _rec getOrDefault ["taskTime", -1];
    if ((_taskTime isNotEqualTo _stamp) && {_curTask in ["RETREAT", "RTB", "TRANSPORT", "TRANSPORTED", "RECON", "ATTACK"]}) then {continue};

    if (_useMorale && {_task in ["ATTACK", "RECON", "REINFORCE", "SUPPORT", "PATROL"]}) then {
        private _until = _rec getOrDefault ["brokenUntil", -1];
        if (_until isEqualType 0 && {_until > time}) then {_task = ""};
    };
    if (_task isEqualTo "") then {continue};

    if (_dueTime <= time) then {
        _due pushBack [[1, 0] select ((_rec getOrDefault ["type", ""]) isEqualTo "INF"), _dueTime, _forEachIndex];
    } else {
        _keep pushBack _x;
    };
} forEach _queue;

// the rest stays queued (a new array: issueOrder below never queues, but keep it clean)
_cmd set ["orderQueue", _keep];
_cmd deleteAt "orderQueueIndex";
if (_due isEqualTo []) exitWith {0};

_due sort true;
private _issued = 0;
private _out = _cmd getOrDefault ["ordersOut", createHashMap];
if !(_out isEqualType createHashMap) then {_out = createHashMap};
{
    (_queue select (_x select 2)) params ["", "_group", "_task", "_pos", "_objective", "_force"];
    if ([_cmd, _group, _task, _pos, _objective, _force] call AIC_fnc_issueOrder) then {
        _issued = _issued + 1;
        if (_task isEqualTo "ATTACK" && {_objective isNotEqualTo ""}) then {_out set [_objective, time]};
    };
} forEach _due;
if (count _out > 0) then {_cmd set ["ordersOut", _out]};

if (_issued > 0 && {!isNil "AIC_ns"} && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["drainOrders: %1 %2 queued order(s) issued, %3 still queued", [_cmd getOrDefault ["side", sideUnknown], _issued, count _keep]] call AIC_fnc_log;
};

_issued
