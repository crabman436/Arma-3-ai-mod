/*
 * Name: AIC_fnc_bestPlace
 * Description:
 *   A spot near a position chosen by the engine's terrain scoring
 *   (selectBestPlaces): an expression over forest, trees, meadow, hills,
 *   houses and sea, each 0..1 at the sample point. Samples are spaced about
 *   a twelfth of the radius apart (8 m at least, 40 m at most), so the call
 *   stays cheap. The best dry spot with a positive score wins; with a flat
 *   size the spot must also be flat and empty for that size (isFlatEmpty),
 *   so a vehicle or helicopter fits.
 *   The one place every position search goes through (landing zones,
 *   assembly areas, overwatch, flanking points, motor pools), so they all
 *   read the terrain the same way.
 *
 * Parameters:
 *   0: ARRAY  - centre position
 *   1: NUMBER - search radius
 *   2: STRING - expression, e.g. "meadow - forest - 3*houses - 10*sea"
 *   3: NUMBER - (optional) flat / empty size the spot must have, 0 = any,
 *               default 0
 *
 * Returns:
 *   ARRAY - [x, y, 0], or [] when nothing scores above zero
 *
 * Example:
 *   private _lz = [_pos, 150, "meadow - forest - 2*trees - 3*houses - 10*sea", 12] call AIC_fnc_bestPlace;
 */

params [
    ["_center", [], [[]]],
    ["_radius", 150, [0]],
    ["_expression", "", [""]],
    ["_flat", 0, [0]]
];

if (count _center < 2 || {_radius <= 0} || {_expression isEqualTo ""}) exitWith {[]};
private _c = [_center select 0, _center select 1, 0];
private _precision = ((_radius / 12) max 8) min 40;

private _found = [];
{
    _x params ["_p", "_score"];
    if (_score <= 0) exitWith {};
    private _q = [_p select 0, _p select 1, 0];
    if (surfaceIsWater _q) then {continue};
    if (_flat > 0 && {(_q isFlatEmpty [_flat, -1, 0.35, _flat, 0, false]) isEqualTo []}) then {continue};
    _found = _q;
    break;
} forEach (selectBestPlaces [_c, _radius, _expression, _precision, 8]);

_found
