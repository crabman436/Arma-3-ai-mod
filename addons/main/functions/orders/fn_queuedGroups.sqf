/*
 * Name: AIC_fnc_queuedGroups
 * Description:
 *   The groups whose planned order still waits in the commander's
 *   "orderQueue" (AIC_fnc_queueOrder, realism D), in one pass over the
 *   queue. A group in it is already promised to a job: the planner counts
 *   it as on that job (AIC_fnc_allocateForces), and the garrison and
 *   transport code leave it alone (AIC_fnc_garrisonCycle donors,
 *   AIC_fnc_findTransport candidates). Dropped entries (empty arrays left by
 *   AIC_fnc_queueOrder until the next AIC_fnc_drainOrders), dead and null
 *   groups are skipped. The queue holds at most one entry per group.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *
 * Returns:
 *   HASHMAP - hashValue group -> queue entry [dueTime, group, task, pos,
 *             objectiveId, force, taskTimeAtQueue, queueTime] (the entry
 *             itself, not a copy: read only)
 *
 * Example:
 *   private _queued = [_cmd] call AIC_fnc_queuedGroups;
 *   if ((hashValue _grp) in _queued) then { ... };
 */

params [["_cmd", createHashMap, [createHashMap]]];

private _out = createHashMap;
if (count _cmd == 0) exitWith {_out};
private _queue = _cmd getOrDefault ["orderQueue", []];
if !(_queue isEqualType []) exitWith {_out};
{
    if (_x isEqualType [] && {count _x >= 5}) then {
        private _g = _x select 1;
        if (_g isEqualType grpNull && {!isNull _g} && {({alive _x} count (units _g)) > 0}) then {
            _out set [hashValue _g, _x];
        };
    };
} forEach _queue;
_out
