/*
    Function: AIC_fnc_ropePoint

    Description:
        A spot to fast-rope a squad into near a position: a street, a yard, a
        clearing. The drop straight down from AIC_ROPE_MAX m must be clear of
        everything (no roof, no tree, no wall: the men come down on the
        ground, never on a roof they could not get off), and nothing within
        AIC_ROPE_ROTOR m of it may stand higher than AIC_ROPE_CLEAR m (the
        rotor hovers above). Never water. Searched outwards in rings from the
        position, nearest first.

    Parameters:
        0: ARRAY  - position
        1: NUMBER - (optional) search radius (m), default 120

    Returns:
        ARRAY - [x, y, 0], or [] if there is no such spot

    Example:
        private _p = [_townPos, 150] call AIC_fnc_ropePoint;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_pos", [], [[]]], ["_radius", 120, [0]]];

if (count _pos < 2) exitWith { [] };
_pos = [_pos select 0, _pos select 1, 0];

// nothing at all in the column above a point, up to _h m
private _fnc_clear = {
    params ["_p", "_h"];
    private _g = AGLToASL [_p select 0, _p select 1, 0];
    (lineIntersectsSurfaces [_g vectorAdd [0, 0, _h], _g vectorAdd [0, 0, 0.6], objNull, objNull, true, 1, "GEOM", "FIRE"]) isEqualTo []
};

private _found = [];
private _rings = [0, 15, 30, 45, 60, 80, 100, 125, 150, 180] select { _x <= _radius };
{
    private _r = _x;
    private _steps = [1, ceil (_r / 8) max 6] select (_r > 0);
    for "_i" from 0 to (_steps - 1) do {
        if (_found isNotEqualTo []) exitWith {};
        private _p = _pos getPos [_r, _i * 360 / _steps];
        _p = [_p select 0, _p select 1, 0];
        if (surfaceIsWater _p) then { continue };
        // the drop itself (and a man's width around it)
        if !([_p, AIC_ROPE_MAX] call _fnc_clear) then { continue };
        if !([_p getPos [1.5, 0], AIC_ROPE_MAX] call _fnc_clear) then { continue };
        if !([_p getPos [1.5, 180], AIC_ROPE_MAX] call _fnc_clear) then { continue };
        // where the rotor turns: nothing higher than AIC_ROPE_CLEAR
        private _rotorOk = true;
        for "_a" from 0 to 315 step 45 do {
            if !([_p getPos [AIC_ROPE_ROTOR, _a], AIC_ROPE_MAX + 20] call {
                params ["_q", "_h"];
                private _g = AGLToASL [_q select 0, _q select 1, 0];
                (lineIntersectsSurfaces [_g vectorAdd [0, 0, _h], _g vectorAdd [0, 0, AIC_ROPE_CLEAR], objNull, objNull, true, 1, "GEOM", "FIRE"]) isEqualTo []
            }) exitWith { _rotorOk = false; };
        };
        if (!_rotorOk) then { continue };
        // fairly level ground to stand on
        if ((surfaceNormal _p) select 2 < 0.9) then { continue };
        _found = _p;
    };
    if (_found isNotEqualTo []) exitWith {};
} forEach _rings;

_found
