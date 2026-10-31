/*
 * Name: AIC_fnc_nearestThreat
 * Description:
 *   Position of the threat cluster or known enemy contact closest to a
 *   position, as far as the commander knows.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: ARRAY   - position
 *   2: NUMBER  - (optional) search range, default AIC_THREAT_RADIUS
 *
 * Returns:
 *   ARRAY - [x, y, 0], or [] if nothing is known within range
 *
 * Example:
 *   private _threatPos = [_cmd, _objPos] call AIC_fnc_nearestThreat;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_pos", [], [[]]],
    ["_range", AIC_THREAT_RADIUS, [0]]
];

if (count _cmd == 0 || {count _pos < 2}) exitWith {[]};

private _best = [];
private _bestDist = _range;
{
    if (_x isEqualType createHashMap) then {
        private _p = _x getOrDefault ["pos", []];
        if (_p isEqualType [] && {count _p >= 2}) then {
            private _d = _p distance2D _pos;
            if (_d < _bestDist) then {
                _bestDist = _d;
                _best = [_p select 0, _p select 1, 0];
            };
        };
    };
} forEach ((_cmd getOrDefault ["threats", []]) + (_cmd getOrDefault ["knownEnemies", []]));

_best
