/*
 * Name: AIC_fnc_queueOrder
 * Description:
 *   Tempo (CONTRACT.md realism part D): a planned order reaches a group
 *   only after a delay, the time it takes the staff to write it and the
 *   messenger to bring it. The order is stored in the commander's
 *   "orderQueue" and given by AIC_fnc_drainOrders once due; the group goes
 *   on with its current task until then.
 *   Delay = setting "orderDelay" x (base + AIC_DELAY_PER_KM s per km between
 *   the HQ and the group's leader):
 *     - forced orders, IDLE, RETREAT, RTB, DEFEND / PATROL of the group's
 *       own "home": 0 (no per-km part either)
 *     - ATTACK, RECON: AIC_DELAY_ATTACK
 *     - SUPPORT: AIC_DELAY_SUPPORT (no per-km part: fire support is radioed)
 *     - DEFEND / PATROL elsewhere, REINFORCE, anything else: AIC_DELAY_MOVE
 *   An order with no delay (also every order with "orderDelay" 0, the old
 *   behaviour) and an order the group already has (same task and
 *   objective, or same task and position within the AIC_fnc_issueOrder
 *   tolerances) go straight to AIC_fnc_issueOrder now, and any order
 *   still queued for the group is dropped: the plan changed its mind.
 *   Otherwise a queued order for the same group is replaced, except by the
 *   same order: then the queued one keeps its due time, so a plan that
 *   repeats itself every cycle does not push its own order back forever.
 *   Queue entry: [dueTime, group, task, pos, objectiveId, force,
 *   taskTimeAtQueue, queueTime]; the last two let AIC_fnc_drainOrders see
 *   whether the group got another order meanwhile.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - group to order
 *   2: STRING  - task (as AIC_fnc_issueOrder)
 *   3: ARRAY   - target position ([] allowed)
 *   4: STRING  - (optional) objective id, default ""
 *   5: BOOL    - (optional) force, default false (a forced order is never delayed)
 *
 * Returns:
 *   BOOL - true if the order was queued, or issued now and AIC_fnc_issueOrder
 *          returned true
 *
 * Example:
 *   [_cmd, _grp, "ATTACK", _obj get "pos", _obj get "id"] call AIC_fnc_queueOrder;
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

_task = toUpperANSI _task;
private _queue = _cmd getOrDefault ["orderQueue", []];
if !(_queue isEqualType []) then {_queue = []};

private _fnc_dropQueued = {
    if ((_queue findIf {(_x select 1) isEqualTo _group}) >= 0) then {
        _cmd set ["orderQueue", _queue select {(_x select 1) isNotEqualTo _group}];
    };
};
private _fnc_issueNow = {
    call _fnc_dropQueued;
    [_cmd, _group, _task, _pos, _objective, _force] call AIC_fnc_issueOrder
};

private _mult = [_cmd, "orderDelay"] call AIC_fnc_getSetting;
if (_mult <= 0 || {_force}) exitWith {call _fnc_issueNow};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then {_groupData = createHashMap};
private _rec = _groupData getOrDefault [hashValue _group, createHashMap];
if (count _rec == 0) exitWith {call _fnc_issueNow};

// --- the order the group already has: nothing to write, nothing to wait for
private _fnc_validPos = {
    params [["_p", []]];
    _p isEqualType [] && {count _p >= 2} && {(_p select 0) isEqualType 0} && {(_p select 1) isEqualType 0}
};
private _curTask = _rec getOrDefault ["task", "IDLE"];
private _curObj = _rec getOrDefault ["objective", ""];
private _curPos = _rec getOrDefault ["taskPos", []];
private _hasIt = _curTask isEqualTo _task && {
    if (_objective isNotEqualTo "") then {_curObj isEqualTo _objective} else {
        private _tol = [AIC_REISSUE_TOL_FIXED, AIC_REISSUE_TOL_MOVING] select (_task in ["ATTACK", "REINFORCE"]);
        _curObj isEqualTo "" && {[_curPos] call _fnc_validPos} && {[_pos] call _fnc_validPos} && {(_curPos distance2D _pos) < _tol}
    }
};
if (_hasIt) exitWith {call _fnc_issueNow};

// --- delay
private _home = _rec getOrDefault ["home", ""];
if !(_home isEqualType "") then {_home = ""};
private _base = switch (true) do {
    case (_task in ["IDLE", "RETREAT", "RTB"]): {0};
    case (_task in ["DEFEND", "PATROL"] && {_home isNotEqualTo ""} && {_objective isEqualTo _home}): {0};
    case (_task in ["ATTACK", "RECON"]): {AIC_DELAY_ATTACK};
    case (_task isEqualTo "SUPPORT"): {AIC_DELAY_SUPPORT};
    default {AIC_DELAY_MOVE};
};
if (_base <= 0) exitWith {call _fnc_issueNow};

private _km = 0;
private _hq = _cmd getOrDefault ["hq", []];
if (_task isNotEqualTo "SUPPORT" && {[_hq] call _fnc_validPos}) then {
    _km = ((getPosATL (leader _group)) distance2D _hq) / 1000;
};
private _delay = _mult * (_base + AIC_DELAY_PER_KM * _km);
if (_delay <= 0) exitWith {call _fnc_issueNow};

// --- the same order already on its way keeps its due time
private _idx = _queue findIf {(_x select 1) isEqualTo _group};
if (_idx >= 0) then {
    private _old = _queue select _idx;
    private _same = (_old select 2) isEqualTo _task && {(_old select 4) isEqualTo _objective} && {
        _objective isNotEqualTo ""
        || {(_old select 3) isEqualTo _pos}
        || {[_old select 3] call _fnc_validPos && {[_pos] call _fnc_validPos}
            && {((_old select 3) distance2D _pos) < ([AIC_REISSUE_TOL_FIXED, AIC_REISSUE_TOL_MOVING] select (_task in ["ATTACK", "REINFORCE"]))}}
    };
    if (_same) exitWith {};
    _idx = -1;
    _queue = _queue select {(_x select 1) isNotEqualTo _group};
};
if (_idx >= 0) exitWith {true};

private _taskTime = _rec getOrDefault ["taskTime", -1];
if !(_taskTime isEqualType 0) then {_taskTime = -1};
// a new array, never changed in place (the queue may be read by a suspended drain)
_cmd set ["orderQueue", _queue + [[time + _delay, _group, _task, +_pos, _objective, _force, _taskTime, time]]];

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["queueOrder: %1 group %2 %3 obj '%4' due in %5 s", [
        _cmd getOrDefault ["side", sideUnknown], groupId _group, _task, _objective, round _delay
    ]] call AIC_fnc_log;
};

true
