/*
    CAI_fnc_buildingsIn
    Enterable, standing buildings in an area.
    Params: 0: ARRAY center, 1: NUMBER radius, 2: NUMBER minimum building positions (default 2)
    Returns: ARRAY of buildings, nearest to the center first
*/

params ["_center", "_radius", ["_minPositions", 2]];

(nearestObjects [_center, ["House", "Building"], _radius]) select {
    alive _x
    && {damage _x < 0.9}
    && {!isObjectHidden _x}
    && {count (_x buildingPos -1) >= _minPositions}
}
