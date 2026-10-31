/*
 * Name: AIC_fnc_nearestBase
 * Description:
 *   The base of a commander closest to a position: objectives with "isBase"
 *   that it owns, plus "BASE_HQ" always. Transport-only crews wait there.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: ARRAY   - position
 *
 * Returns:
 *   STRING - objective id, "" if there is none
 *
 * Example:
 *   private _base = [_cmd, getPosATL _truck] call AIC_fnc_nearestBase;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_pos", [], [[]]]
];

if (count _cmd == 0 || {count _pos < 2}) exitWith {""};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _best = "";
private _bestDist = 1e9;
{
    if (_x isEqualType createHashMap) then {
        private _id = _x getOrDefault ["id", ""];
        private _p = _x getOrDefault ["pos", []];
        if (
            (_x getOrDefault ["isBase", false]) isEqualTo true
            && {_id isEqualTo AIC_BASE_ID || {(_x getOrDefault ["owner", sideUnknown]) isEqualTo _side}}
            && {count _p >= 2}
            && {(_p distance2D _pos) < _bestDist}
        ) then {
            _bestDist = _p distance2D _pos;
            _best = _id;
        };
    };
} forEach (_cmd getOrDefault ["objectives", []]);

_best
