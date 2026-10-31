/*
 * Name: AIC_fnc_splitForAttack
 * Description:
 *   Splits a big infantry squad into two fireteams as it nears its attack
 *   target (called by AIC_fnc_monitorOrders, which has checked the size, the
 *   distance and the cooldown). The original group keeps going straight in,
 *   the new team swings around one side through a flanking point and comes in
 *   from there. Only done when the squad is not in a fight right now and is
 *   clearly stronger than what is known at the target: threat clusters near
 *   it must have less than 75 % of the squad's power, so two weak teams are
 *   never fed into something the whole squad could only just handle.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - attacking squad
 *   2: HASHMAP - its group record
 *   3: ARRAY   - attack target
 *   4: STRING  - objective id ("" = none)
 *
 * Returns:
 *   BOOL - true if the squad was split
 *
 * Example:
 *   [_cmd, _group, _rec, _taskPos, _objId] call AIC_fnc_splitForAttack;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_rec", createHashMap, [createHashMap]],
    ["_target", [], [[]]],
    ["_objective", "", [""]]
];

if (!isServer || {count _rec == 0} || {count _target < 2}) exitWith {false};

// not in the middle of a fight
private _engaged = _rec getOrDefault ["lastEngaged", -1e6];
if ((_engaged isEqualType 0 && {(time - _engaged) < 60}) || {(behaviour (leader _group)) isEqualTo "COMBAT"}) exitWith {false};

// clearly stronger than what is known there
private _enemy = 0;
{
    if (_x isEqualType createHashMap && {((_x getOrDefault ["pos", [0, 0, 0]]) distance2D _target) < 500}) then {
        private _p = _x getOrDefault ["power", 0];
        if (_p isEqualType 0) then {_enemy = _enemy + _p};
    };
} forEach (_cmd getOrDefault ["threats", []]);
if (_enemy > 0.75 * (_rec getOrDefault ["power", 0])) exitWith {false};

// a flanking point on dry land, on either side of the line of advance
private _dir = _target getDir (leader _group);
private _reach = ((((leader _group) distance2D _target) * 0.8) min 450) max 200;
private _via = [];
{
    private _p = _target getPos [_reach, _dir + _x];
    if (!surfaceIsWater _p) exitWith {_via = [_p select 0, _p select 1, 0]};
} forEach ([[60, -60], [-60, 60]] select (random 1 < 0.5));
if (_via isEqualTo []) exitWith {false};
// cover on the way around, if there is any close by
private _covered = [_via, 120, "forest + trees - 2*houses - 10*sea"] call AIC_fnc_bestPlace;
if (_covered isNotEqualTo []) then {_via = _covered};

private _new = [_cmd, _group, 2] call AIC_fnc_splitGroup;
if (_new isEqualTo []) exitWith {false};

// splitting cleared the waypoints: same order again, straight in
[_cmd, _group, "ATTACK", _target, _objective, true] call AIC_fnc_issueOrder;

private _team = _new select 0;
_team setVariable ["AIC_attackVia", _via];
[_cmd, _team, "ATTACK", _target, _objective] call AIC_fnc_issueOrder;

["%1: squad %2 splits for the attack, team %3 flanks via %4", [
    _cmd getOrDefault ["side", sideUnknown], groupId _group, groupId _team, _via apply {round _x}
]] call AIC_fnc_log;

true
