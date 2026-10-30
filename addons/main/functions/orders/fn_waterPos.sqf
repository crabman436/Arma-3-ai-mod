/*
 * Name: AIC_fnc_waterPos
 * Description:
 *   Finds a water position for naval groups: the position itself if it is
 *   on water, otherwise the first water point on the line from the
 *   position towards a reference (usually the group leader), searched in
 *   50 m steps up to a maximum distance.
 *
 * Parameters:
 *   0: ARRAY          - position [x,y] or [x,y,z]
 *   1: ARRAY / OBJECT - (optional) reference position or object giving the
 *                       search direction; invalid / missing = north
 *   2: NUMBER         - (optional) max search distance in m, default 1000
 *
 * Returns:
 *   ARRAY - [x,y,0] on water, or [] if none was found
 *
 * Example:
 *   private _water = [_target, leader _group, 1000] call AIC_fnc_waterPos;
 */

params [
    ["_pos", [], [[]]],
    ["_from", [], [[], objNull]],
    ["_maxDist", 1000, [0]]
];

if (count _pos < 2) exitWith {[]};
private _p = [_pos select 0, _pos select 1, 0];
if (surfaceIsWater _p) exitWith {_p};

private _validFrom = if (_from isEqualType objNull) then { !isNull _from } else { count _from >= 2 };
private _dir = if (_validFrom) then { _p getDir _from } else { 0 };

private _water = [];
for "_d" from 50 to _maxDist step 50 do {
    private _try = _p getPos [_d, _dir];
    if (surfaceIsWater _try) exitWith { _water = [_try select 0, _try select 1, 0]; };
};
_water
