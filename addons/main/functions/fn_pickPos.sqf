/*
    CAI_fnc_pickPos
    Picks a position around an objective by line of sight to it: either a
    concealed spot (attack positions, out of the defenders' view) or one with
    a clear view (support-by-fire positions for vehicles). Samples a sector
    and keeps the best spot; never water.

    Params:
        0: ARRAY objective center
        1: NUMBER direction from the center to search in
        2: NUMBER minimum distance
        3: NUMBER maximum distance
        4: BOOL true = wants a view of the objective, false = wants cover from it
        5: NUMBER objective radius (to also check its edges)
        6: NUMBER sector half-width in degrees (default 35)
    Returns: ARRAY position [x, y, 0]
*/

params ["_center", "_dir", "_minD", "_maxD", "_wantView", ["_radius", 100], ["_spread", 35]];

private _targets = [
    _center,
    _center getPos [_radius * 0.4, _dir + 90],
    _center getPos [_radius * 0.4, _dir - 90]
] apply {AGLToASL [_x select 0, _x select 1, 2]};

private _best = [];
private _bestScore = -1e9;
for "_i" from 0 to 11 do {
    private _p = _center getPos [_minD + random (_maxD - _minD), _dir - _spread + random (2 * _spread)];
    if (!surfaceIsWater _p) then {
        private _eye = AGLToASL [_p select 0, _p select 1, 2.5];
        private _vis = 0;
        {_vis = _vis + ([objNull, "VIEW", objNull] checkVisibility [_eye, _x])} forEach _targets;
        _vis = _vis / count _targets;
        private _score = ([1 - _vis, _vis] select _wantView) + random 0.05;
        if (_score > _bestScore) then {_bestScore = _score; _best = _p};
    };
};

if (_best isEqualTo []) then {
    _best = [_center getPos [(_minD + _maxD) / 2, _dir], _center] call CAI_fnc_landPos;
};
[_best select 0, _best select 1, 0]
