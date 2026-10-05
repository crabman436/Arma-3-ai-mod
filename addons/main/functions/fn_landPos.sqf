/*
    CAI_fnc_landPos
    Moves a position out of the water, stepping toward a reference point.
    Params: 0: ARRAY position, 1: ARRAY position to step toward
    Returns: ARRAY position [x, y, 0]
*/

params ["_pos", "_toward"];

private _p = [_pos select 0, _pos select 1, 0];
private _i = 0;
while {surfaceIsWater _p && {_i < 20}} do {
    _p = _p getPos [50, _p getDir _toward];
    _i = _i + 1;
};
[_p select 0, _p select 1, 0]
