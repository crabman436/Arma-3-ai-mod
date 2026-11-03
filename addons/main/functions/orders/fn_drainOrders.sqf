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
 *       (ATTACK, RECON, REINFORCE, SUPPORT, PATROL).
 *   An order the group already has is skipped by AIC_fnc_issueOrder's
 *   same-order check (queued orders are never forced: forced orders are
 *   not delayed).
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

params [["_cmd", createHashMap, [createHashMap]]];

if (!isServer) exitWith {0};
if (count _cmd == 0) exitWith {0};

private _queue = _cmd getOrDefault ["orderQueue", []];
if (!(_queue isEqualType []) || {_queue isEqualTo []}) exitWith {0};

private _groupData = _cmd getOrDefault ["groupData", createHashMap];
if !(_groupData isEqualType createHashMap) then {_groupData = createHashMap};
private _useMorale = ([_cmd, "useMorale"] call AIC_fnc_getSetting) isEqualTo true;

private _keep = [];
private _due = [];   // [infantry 0 / other 1, dueTime, index into _queue]
{
    _x params [["_dueTime", 0, [0]], ["_group", grpNull, [grpNull]], ["_task", "", [""]], "", "", "", ["_stamp", -1, [0]]];
    if (isNull _group || {({alive _x} count (units _group)) == 0}) then {continue};
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
