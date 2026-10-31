/*
 * Name: AIC_fnc_sentryWatch
 * Description:
 *   The alarm. Each cycle the sentries of a garrisoned infantry group (unit
 *   variable "AIC_sentry", posted by AIC_fnc_garrisonBuildings) are asked
 *   what they know within AIC_SENTRY_RANGE (nearTargets). The first target
 *   a sentry has recognised as a hostile side raises the alarm for the
 *   place the group defends:
 *     - the objective record gets "alarmTime" (time) and "alarmPos" (the
 *       perceived position); AIC_fnc_garrisonCycle stands the garrison to
 *       on it, AIC_fnc_alarmPos gives the defenders a side to face;
 *     - every group of the place (record "home" or "objective" is it) is
 *       woken and told about the target (reveal), so its leader's own intel
 *       picks it up next cycle;
 *     - one log line, "alarm at ...".
 *   One alarm per place per AIC_ALARM_REPEAT seconds.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - infantry group on DEFEND with its garrison in place
 *   2: HASHMAP - its group record
 *
 * Returns:
 *   BOOL - true if an alarm was raised
 *
 * Example:
 *   [_cmd, _group, _rec] call AIC_fnc_sentryWatch;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_rec", createHashMap, [createHashMap]]
];

if (!isServer || {isNull _group} || {count _rec == 0}) exitWith {false};
private _sentries = (units _group) select {alive _x && {_x getVariable ["AIC_sentry", false]}};
if (_sentries isEqualTo []) exitWith {false};

private _id = _rec getOrDefault ["objective", ""];
if (!(_id isEqualType "") || {_id isEqualTo ""}) then {_id = _rec getOrDefault ["home", ""]};
private _obj = [_cmd, _id] call AIC_fnc_getObjective;
if (count _obj == 0) exitWith {false};
if ((time - (_obj getOrDefault ["alarmTime", -1e6])) < AIC_ALARM_REPEAT) exitWith {false};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _spotted = objNull;
private _where = [];
{
    private _sentry = _x;
    {
        _x params ["_tPos", "", "_tSide", "", "_target"];
        if (
            !isNull _target && {alive _target}
            && {_tSide in [west, east, independent, civilian]}
            && {_tSide != _side}
            && {(_side getFriend _tSide) < AIC_HOSTILE_FRIEND}
        ) exitWith {
            _spotted = _target;
            _where = [_tPos select 0, _tPos select 1, 0];
        };
    } forEach (_sentry nearTargets AIC_SENTRY_RANGE);
    if (!isNull _spotted) exitWith {};
} forEach _sentries;
if (isNull _spotted) exitWith {false};

_obj set ["alarmTime", time];
_obj set ["alarmPos", _where];

// the whole place wakes and learns of it
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _told = 0;
{
    private _r = _y;
    if (_r isEqualType createHashMap && {(_r getOrDefault ["home", ""]) isEqualTo _id || {(_r getOrDefault ["objective", ""]) isEqualTo _id}}) then {
        private _g = _r getOrDefault ["group", grpNull];
        if (!isNull _g) then {
            [_cmd, _g, false] call AIC_fnc_setGroupSim;
            _g reveal [_spotted, 2.5];
            _told = _told + 1;
        };
    };
} forEach _groupData;

["%1: alarm at '%2': a sentry of group %3 spotted %4 at %5, %6 groups told", [
    _side, _obj getOrDefault ["name", _id], groupId _group, typeOf _spotted, mapGridPosition _where, _told
]] call AIC_fnc_log;

true
