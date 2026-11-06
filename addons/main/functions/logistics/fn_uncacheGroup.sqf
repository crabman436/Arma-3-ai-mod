/*
    Function: AIC_fnc_uncacheGroup

    Description:
        Brings back the men AIC_fnc_cacheGroup stored: each one is created in
        his group where he stood, with his class, loadout, direction, damage,
        skill, rank, stance and garrison variables, and gets AIC's unit
        event handlers. A garrison man stays at his spot (doStop). The
        leader's damage is on again; the record's "cache" is cleared. The
        group keeps its parked state (the engine freezes the new men too)
        until something wakes it. Called by AIC_fnc_setGroupSim before any
        wake (so an order never reaches half a group) and by
        AIC_fnc_cacheCycle when a player or an enemy comes close. Server
        only.

    Parameters:
        0: HASHMAP - commander
        1: GROUP   - the group

    Returns:
        NUMBER - men brought back

    Example:
        [_cmd, _group] call AIC_fnc_uncacheGroup;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]], ["_group", grpNull, [grpNull]]];

if (!isServer || { isNull _group }) exitWith { 0 };
private _rec = (_cmd getOrDefault ["groupData", createHashMap]) getOrDefault [hashValue _group, createHashMap];
private _cache = _rec getOrDefault ["cache", []];
if (_cache isEqualTo []) exitWith { 0 };

private _made = 0;
isNil {
    _rec set ["cache", []];
    _rec set ["cacheTime", -1];
    private _leader = leader _group;
    if (!isNull _leader) then { _leader allowDamage true; };
    {
        _x params ["_class", "_loadout", "_posASL", "_dir", "_damage", "_skill", "_rank", "_unitPos", "_vars"];
        private _u = _group createUnit [_class, ASLToAGL _posASL, [], 0, "CAN_COLLIDE"];
        if (isNull _u) then { continue };
        _u setPosASL _posASL;
        _u setDir _dir;
        _u setUnitLoadout _loadout;
        _u setDamage _damage;
        _u setSkill _skill;
        _u setRank _rank;
        _u setUnitPos _unitPos;
        { _u setVariable [_x select 0, _x select 1]; } forEach _vars;
        // a garrison man stays at his spot instead of running into formation
        if ((_u getVariable ["AIC_garrisonSpot", []]) isNotEqualTo []) then { doStop _u; };
        [_cmd, _group, _u] call AIC_fnc_attachGroupEHs;
        _made = _made + 1;
    } forEach _cache;
};
["cache: %1 brought back %2 men of group %3", [_cmd getOrDefault ["side", sideUnknown], _made, groupId _group]] call AIC_fnc_log;
_made
