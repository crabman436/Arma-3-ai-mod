/*
 * Name: AIC_fnc_newGroupRecord
 * Description:
 *   Builds a fresh, complete group record for a group that comes under
 *   command (see CONTRACT.md, "Group record"): type via
 *   AIC_fnc_classifyGroup, power via AIC_fnc_groupPower, task "IDLE" and
 *   every logistics key ("parked", "home", "transport", "final"). The one
 *   place a record is created, used by AIC_fnc_registerGroups,
 *   AIC_fnc_updateGroups and AIC_fnc_issueOrder, so no record can ever
 *   lack a key.
 *
 * Parameters:
 *   0: GROUP - group
 *
 * Returns:
 *   HASHMAP - new group record
 *
 * Example:
 *   _groupData set [hashValue _grp, [_grp] call AIC_fnc_newGroupRecord];
 */

params [["_group", grpNull, [grpNull]]];

private _aliveCount = if (isNull _group) then { 0 } else { {alive _x} count (units _group) };

createHashMapFromArray [
    ["group", _group],
    ["type", [_group] call AIC_fnc_classifyGroup],
    ["power", [_group] call AIC_fnc_groupPower],
    ["initialSize", _aliveCount max 1],
    ["strength", 1],
    ["task", "IDLE"],
    ["taskPos", []],
    ["taskTime", time],
    ["objective", ""],
    ["transportOnly", false],
    ["parked", false],
    ["home", ""],
    ["transport", grpNull],
    ["final", createHashMap]
]
