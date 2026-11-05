/*
    Function: AIC_fnc_cacheGroup

    Description:
        Caches a parked infantry group: every member but the leader is
        stored in the group record and deleted, so far from players and
        enemies they cost nothing at all (no AI, no physics, no network).
        The leader stays where he is (parked, frozen, damage off while
        cached), so the group and its record, home and orders stay valid and
        the planner keeps counting the group with its stored power and
        strength (AIC_fnc_updateGroups leaves a cached record alone).
        AIC_fnc_uncacheGroup brings the men back; AIC_fnc_cacheCycle decides
        when. Server only, a group local to the server.

        Record key "cache": one entry per stored man, [class, loadout,
        position ASL, direction, damage, skill, rank, unitPos, [unit
        variables]] (the garrison variables "AIC_garrisonSpot",
        "AIC_garrisonStance", "AIC_sentry", "AIC_buildingPos"); "cacheTime".

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - the group

    Returns:
        NUMBER - men stored (0: nothing done)

    Example:
        [_cmd, _group] call AIC_fnc_cacheGroup;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]], ["_group", grpNull, [grpNull]]];

if (!isServer || { isNull _group } || { !local _group }) exitWith { 0 };
private _rec = (_cmd getOrDefault ["groupData", createHashMap]) getOrDefault [hashValue _group, createHashMap];
if (count _rec == 0 || { (_rec getOrDefault ["cache", []]) isNotEqualTo [] }) exitWith { 0 };

private _leader = leader _group;
private _men = (units _group) select { alive _x && { _x isNotEqualTo _leader } };
if (!alive _leader || { _men isEqualTo [] } || { ((units _group) findIf { isPlayer _x || { !isNull objectParent _x } }) >= 0 }) exitWith { 0 };

private _vars = ["AIC_garrisonSpot", "AIC_garrisonStance", "AIC_sentry", "AIC_buildingPos"];
private _cache = _men apply {
    private _u = _x;
    [typeOf _u, getUnitLoadout _u, getPosASL _u, getDir _u, damage _u, skill _u, rank _u, unitPos _u,
        _vars apply { [_x, _u getVariable _x] } select { !isNil { _x select 1 } }]
};
// all in one frame: no cycle sees half a group
isNil {
    { deleteVehicle _x; } forEach _men;
    _leader allowDamage false;
    _rec set ["cache", _cache];
    _rec set ["cacheTime", time];
};
["cache: %1 stored %2 men of group %3", [_cmd getOrDefault ["side", sideUnknown], count _cache, groupId _group]] call AIC_fnc_log;
count _cache
