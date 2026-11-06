/*
    Function: AIC_fnc_ropeOrigins

    Description:
        Where fast ropes hang from a helicopter: model-space points just
        outside its cargo doors (or its rear ramp). Known vanilla airframes
        use fixed points (the same spots ACE3 uses); any other helicopter
        gets points from its cargo get-in memory points ("memoryPointsGetInCargo",
        a little inside and above them, one per side; a door on one side only
        is mirrored to the other). Every point is then checked on the
        helicopter itself: a line straight down from it must not hit the
        helicopter (skids, sponsons, the hull); a blocked point is moved
        outwards in 0.25 m steps (up to 1.5 m) or dropped (a known point is
        kept as it is). The result is
        cached per vehicle class (missionNamespace "AIC_ropeOriginCache").
        Planes, and helicopters without cargo seats, get none.

    Parameters:
        0: OBJECT - helicopter (must exist in the world for the check)

    Returns:
        ARRAY - model-space points [[x, y, z], ...], [] if it cannot fast rope

    Example:
        private _origins = [_heli] call AIC_fnc_ropeOrigins;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_veh", objNull, [objNull]]];

if (isNull _veh || { !(_veh isKindOf "Helicopter") }) exitWith { [] };
private _cls = typeOf _veh;
private _cache = missionNamespace getVariable ["AIC_ropeOriginCache", createHashMap];
if (_cls in _cache) exitWith { +(_cache get _cls) };

private _cfg = configOf _veh;
private _seats = getNumber (_cfg >> "transportSoldier");
// (cargo seats, or FFV / bench seats, which are turrets: a squad rides in either)
if (_seats < 1 && { (fullCrew [_veh, "cargo", true]) isEqualTo [] } && { ((fullCrew [_veh, "turret", true]) findIf { (_x param [4, false]) isEqualTo true }) < 0 }) exitWith {
    _cache set [_cls, []];
    missionNamespace setVariable ["AIC_ropeOriginCache", _cache];
    []
};

// fixed points of the vanilla airframes (as ACE3 configures them)
private _known = [
    ["O_Heli_Transport_04_bench_F", [[1.03, 1.6, -0.23], [1.03, -1.36, -0.23], [-1.23, 1.6, -0.23], [-1.23, -1.36, -0.23]]],
    ["O_Heli_Transport_04_covered_F", [[0.83, -4.7, -0.03], [-1.02, -4.7, -0.03]]],
    ["Heli_Light_02_base_F", [[1.41, 1.38, 0], [-1.41, 1.38, 0]]],
    ["Heli_Attack_02_base_F", [[1.25, 1.5, -0.6], [-1.1, 1.5, -0.6]]],
    ["Heli_Transport_02_base_F", [[0.94, -4.82, -1.16], [-0.94, -4.82, -1.16]]],
    ["Heli_Transport_03_base_F", [[0.75, -5.29, -0.11], [-0.87, -5.29, -0.11]]]
];
private _pts = [];
private _trusted = false;
{
    _x params ["_base", "_p"];
    if (_veh isKindOf _base) exitWith { _pts = +_p; _trusted = true; };
} forEach _known;

if (_pts isEqualTo []) then {
    // from the cargo get-in points: a little in from them and at door height
    private _mp = _cfg >> "memoryPointsGetInCargo";
    private _names = if (isArray _mp) then { getArray _mp } else { if (isText _mp) then { [getText _mp] } else { [] } };
    private _left = []; private _right = [];
    {
        private _p = _veh selectionPosition [_x, "Memory"];
        if (_p isNotEqualTo [0, 0, 0]) then {
            private _q = [(_p select 0) * 0.85, _p select 1, (_p select 2) + 1.0];
            if ((_q select 0) >= 0) then { _right pushBack _q; } else { _left pushBack _q; };
        };
    } forEach _names;
    // one per side (the most forward one: the main door)
    _right = [_right, [], { _x select 1 }, "DESCEND"] call BIS_fnc_sortBy;
    _left = [_left, [], { _x select 1 }, "DESCEND"] call BIS_fnc_sortBy;
    if (_right isNotEqualTo []) then { _pts pushBack (_right select 0); };
    if (_left isNotEqualTo []) then { _pts pushBack (_left select 0); };
    // a rear ramp only (one point on the centre line): two ropes side by side;
    // a door on one side only: the other side's mirror (airframes are symmetric)
    if (count _pts == 1) then {
        private _c = _pts select 0;
        _pts = if (abs (_c select 0) < 0.4) then {
            [[0.8, _c select 1, _c select 2], [-0.8, _c select 1, _c select 2]]
        } else {
            [_c, [-(_c select 0), _c select 1, _c select 2]]
        };
    };
};

// nothing of the helicopter below a point (a man would slide into it)
private _ok = [];
private _blocked = [];
{
    private _p = +_x;
    private _out = [1, -1] select ((_p select 0) < 0);
    // (a point on the centre line, a ramp, moves back instead)
    private _axis = [0, 1] select (abs (_p select 0) < 0.3);
    for "_i" from 0 to 6 do {
        private _q = +_p;
        if (_axis == 0) then { _q set [0, (_p select 0) + _out * 0.25 * _i]; } else { _q set [1, (_p select 1) - 0.25 * _i]; };
        private _w = _veh modelToWorldWorld _q;
        private _hits = lineIntersectsSurfaces [_w, _w vectorAdd [0, 0, -12], objNull, objNull, true, -1, "GEOM", "NONE"];
        if ((_hits findIf { (_x select 2) isEqualTo _veh || { (_x select 3) isEqualTo _veh } }) < 0) exitWith {
            _ok pushBack _q;
        };
        // (a known point that stays blocked: kept as it is, ACE3 ropes from it,
        // unless two clear ones are left without it)
        if (_i == 6 && { _trusted }) then { _blocked pushBack _p; };
    };
} forEach _pts;

if (count _ok < 2) then { _ok append _blocked; };
_cache set [_cls, _ok];
missionNamespace setVariable ["AIC_ropeOriginCache", _cache];
+_ok
