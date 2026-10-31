/*
 * Name: AIC_fnc_alarmPos
 * Description:
 *   Where a place's sentries last saw the enemy (AIC_fnc_sentryWatch), if
 *   that was within AIC_ALARM_TIME seconds: the side a garrison faces when
 *   the commander knows of no threat cluster yet.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: STRING  - objective id
 *
 * Returns:
 *   ARRAY - [x, y, 0], or [] without a fresh alarm
 *
 * Example:
 *   private _threatPos = [_cmd, _objective] call AIC_fnc_alarmPos;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_id", "", [""]]
];

if (count _cmd == 0 || {_id isEqualTo ""}) exitWith {[]};
private _obj = [_cmd, _id] call AIC_fnc_getObjective;
if ((time - (_obj getOrDefault ["alarmTime", -1e6])) >= AIC_ALARM_TIME) exitWith {[]};
private _p = _obj getOrDefault ["alarmPos", []];
if (count _p < 2) exitWith {[]};
[_p select 0, _p select 1, 0]
