/*
 * Name: AIC_fnc_refillGroup
 * Description:
 *   Replaces the dead of a group that is back at a base (server; setting
 *   "replaceLosses"). New men of the classes the group was registered
 *   with (record "roster", AIC_fnc_newGroupRecord; else the leader's
 *   class) are made beside the leader, up to its "initialSize", with the
 *   group's average skill and the commander's unit handlers
 *   (AIC_fnc_attachGroupEHs). A base gives at most
 *   "replaceLossesPerHour" men an hour (commander key "refills": base id
 *   -> times), only while the side holds it and no threat cluster or
 *   known contact is within AIC_THREAT_RADIUS of it. Nothing for a group
 *   with a player, one riding, or one that is not infantry / motorised /
 *   mechanised / armoured.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - the group
 *   2: STRING  - base objective id
 *
 * Returns:
 *   NUMBER - men made
 *
 * Example:
 *   private _n = [_cmd, _group, "BASE_HQ"] call AIC_fnc_refillGroup;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_baseId", "", [""]]
];

if (!isServer || { count _cmd == 0 } || { isNull _group } || { _baseId isEqualTo "" }) exitWith { 0 };
if !(([_cmd, "replaceLosses"] call AIC_fnc_getSetting) isEqualTo true) exitWith { 0 };
private _side = _cmd getOrDefault ["side", sideUnknown];
private _base = [_cmd, _baseId] call AIC_fnc_getObjective;
private _basePos = _base getOrDefault ["pos", []];
if (count _base == 0 || { (_base getOrDefault ["owner", sideUnknown]) isNotEqualTo _side } || { !(_basePos isEqualType []) } || { count _basePos < 2 }) exitWith { 0 };
if (([_cmd, _basePos, AIC_THREAT_RADIUS] call AIC_fnc_nearestThreat) isNotEqualTo []) exitWith { 0 };

private _rec = (_cmd getOrDefault ["groupData", createHashMap]) getOrDefault [hashValue _group, createHashMap];
if (count _rec == 0) exitWith { 0 };
if (!((_rec getOrDefault ["type", ""]) in ["INF", "MOTOR", "MECH", "ARMOR"]) || { (_rec getOrDefault ["task", ""]) in ["TRANSPORT", "TRANSPORTED"] }) exitWith { 0 };
// a cached group has only its leader in the world (record "cache"): its men
// come back with AIC_fnc_uncacheGroup, the refill waits for that ("refillDue")
if ((_rec getOrDefault ["cache", []]) isNotEqualTo []) exitWith { 0 };
private _alive = (units _group) select { alive _x };
if (_alive isEqualTo [] || { (_alive findIf { isPlayer _x }) >= 0 }) exitWith { 0 };
private _leader = leader _group;
if (isNull _leader || { !alive _leader } || { !isNull objectParent _leader && { !([objectParent _leader] call AIC_fnc_isLanded) } }) exitWith { 0 };

private _initial = _rec getOrDefault ["initialSize", count _alive];
if !(_initial isEqualType 0) then { _initial = count _alive };
private _missing = (round _initial) - (count _alive);
if (_missing <= 0) exitWith { 0 };

// the base's budget: men in the last hour
private _perHour = round (([_cmd, "replaceLossesPerHour"] call AIC_fnc_getSetting) max 0);
private _refills = _cmd getOrDefault ["refills", createHashMap];
if !(_refills isEqualType createHashMap) then { _refills = createHashMap };
_cmd set ["refills", _refills];
private _log = (_refills getOrDefault [_baseId, []]) select { (time - _x) < 3600 };
private _budget = (_perHour - (count _log)) max 0;
if (_budget <= 0) exitWith {
    ["refill: base '%1' has no replacements left this hour for group %2", [_baseId, groupId _group]] call AIC_fnc_log;
    0
};
private _n = _missing min _budget;

// the classes: the roster the group was registered with, else the leader's
private _roster = _rec getOrDefault ["roster", []];
if !(_roster isEqualType []) then { _roster = [] };
// (a class of a mod no longer loaded is no use; none left: the leader's)
_roster = _roster select { _x isEqualType "" && { isClass (configFile >> "CfgVehicles" >> _x) } };
if (_roster isEqualTo []) then { _roster = [typeOf _leader] };
private _have = _alive apply { typeOf _x };
// the ones missing from the roster first, then the roster over again
private _classes = +_roster;
{ private _i = _classes find _x; if (_i >= 0) then { _classes deleteAt _i }; } forEach _have;
while { count _classes < _n } do { _classes append _roster };

private _skill = 0;
{ _skill = _skill + (skill _x) } forEach _alive;
_skill = _skill / (count _alive);
// beside the leader (or his vehicle), on a free spot: not in a wall or a hull
private _lPos = getPosATL (vehicle _leader);
private _made = 0;
for "_i" from 0 to (_n - 1) do {
    private _cls = _classes select _i;
    private _p = (_lPos getPos [6, random 360]) findEmptyPosition [0, 25, _cls];
    if (_p isEqualTo []) then { _p = _lPos getPos [8 + random 8, random 360]; };
    private _u = _group createUnit [_cls, [_p select 0, _p select 1, 0], [], 0, "CAN_COLLIDE"];
    if (isNull _u) then { continue };
    _u setSkill _skill;
    [_cmd, _group, _u] call AIC_fnc_attachGroupEHs;
    _log pushBack time;
    _made = _made + 1;
};
_refills set [_baseId, _log];
if (_made > 0) then {
    ["refill: %1 men join group %2 at '%3' (%4 of %5 this hour)", [_made, groupId _group, _baseId, count _log, _perHour]] call AIC_fnc_log;
};
_made
