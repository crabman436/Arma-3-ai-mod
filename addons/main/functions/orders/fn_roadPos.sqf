/*
 * Name: AIC_fnc_roadPos
 * Description:
 *   Snaps a position to the nearest road segment within a radius. Used by
 *   the order functions to give vehicles road-friendly waypoints.
 *   Returns the position itself (z = 0) when no road is in range.
 *
 * Parameters:
 *   0: ARRAY  - position [x,y] or [x,y,z]
 *   1: NUMBER - (optional) search radius in m, default 150
 *
 * Returns:
 *   ARRAY - [x,y,0] of the nearest road, or of the input position
 *           ([] for an invalid position)
 *
 * Example:
 *   private _p = [_target getPos [450, _dir], 200] call AIC_fnc_roadPos;
 */

params [
    ["_pos", [], [[]]],
    ["_radius", 150, [0]]
];

if (count _pos < 2) exitWith {[]};
private _p = [_pos select 0, _pos select 1, 0];

private _roads = _p nearRoads _radius;
if (_roads isEqualTo []) exitWith {_p};

private _best = objNull;
private _bestD = 1e10;
{
    private _d = _x distance2D _p;
    if (_d < _bestD) then { _bestD = _d; _best = _x; };
} forEach _roads;

private _rp = getPosATL _best;
[_rp select 0, _rp select 1, 0]
