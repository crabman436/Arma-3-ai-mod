/*
 * Name: AIC_fnc_garrisonLayout
 * Description:
 *   The lie of a place its garrison is laid out on, read from the terrain
 *   once per objective (cached in the objective key "layout" together with
 *   the radius it was made for; terrain never changes). Shared by
 *   AIC_fnc_garrisonPost (where each infantry group holds) and
 *   AIC_fnc_garrisonVehicles (where each vehicle stands):
 *     - "builtR": the radius of the built-up area: the distance within
 *       which 90 % of the houses inside the objective radius stand (at
 *       least 60 m). A place with fewer than AIC_LAYOUT_MIN_HOUSES houses
 *       (an airfield, open ground) is built up to its whole radius.
 *     - "large": the built-up area is wider than AIC_POST_LARGE: such a
 *       place is held in posts spread over it instead of one spot in the
 *       middle.
 *     - "ringR": the defensive ring, = "builtR".
 *     - "approaches": the roads coming in, [bearing, road position,
 *       outward direction, road width], at most AIC_APPROACH_MAX, at least
 *       AIC_APPROACH_GAP degrees apart: road segments (main road, road,
 *       track; no footpaths or bridges) crossing the band from 0.7 x ring
 *       to ring + 100 m that run outwards (within ~50 degrees of radial),
 *       the ones nearest ring + 20 m first.
 *     - "outposts": [bearing, position] every 45 degrees at 0.85 x ring:
 *       high open ground off the houses, trees, roads and runways
 *       (AIC_fnc_bestPlace, flat for a vehicle), where a vehicle or an
 *       observation post stands when no road comes in from that side.
 *
 * Parameters:
 *   0: HASHMAP - objective record ("pos", "radius")
 *
 * Returns:
 *   HASHMAP - "radius", "builtR", "ringR", "large", "houses", "approaches",
 *             "outposts" (empty map for a record without position)
 *
 * Example:
 *   private _layout = [_objRec] call AIC_fnc_garrisonLayout;
 *   if (_layout get "large") then { ... };
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_obj", createHashMap, [createHashMap]]];

private _c = _obj getOrDefault ["pos", []];
if (!(_c isEqualType []) || {count _c < 2}) exitWith {createHashMap};
_c = [_c select 0, _c select 1, 0];
private _r = _obj getOrDefault ["radius", 300];
if (!(_r isEqualType 0) || {_r <= 0}) then {_r = 300};

// made once per objective (and again should the radius change)
private _layout = _obj getOrDefault ["layout", createHashMap];
if (_layout isEqualType createHashMap && {(_layout getOrDefault ["radius", -1]) isEqualTo _r}) exitWith {_layout};

// --- the built-up area ---------------------------------------------------------
// (map objects, nearest first: cheap even over a city)
private _houses = nearestTerrainObjects [_c, ["HOUSE", "BUILDING", "CHURCH", "CHAPEL", "HOSPITAL", "FUELSTATION"], _r, true, true];
private _n = count _houses;
private _builtR = if (_n < AIC_LAYOUT_MIN_HOUSES) then {
    _r
} else {
    (((_houses select (floor (0.9 * (_n - 1)))) distance2D _c) max 60) min _r
};
private _ringR = _builtR;
private _large = _builtR > AIC_POST_LARGE;

private _fnc_angDiff = {params ["_a", "_b"]; abs (((_a - _b + 540) % 360) - 180)};

// --- the approaches: roads coming in across the ring ------------------------------
private _cands = [];
{
    private _d = _x distance2D _c;
    if (_d < (_ringR * 0.7) || {_d > (_ringR + 100)}) then {continue};
    private _info = getRoadInfo _x;
    _info params ["_type", "_w", "_ped", "", "", "", "_beg", "_end", ["_bridge", false]];
    if (!(_type in ["MAIN ROAD", "ROAD", "TRACK"]) || {_ped} || {_bridge}) then {continue};
    private _rp = getPosATL _x;
    _rp = [_rp select 0, _rp select 1, 0];
    private _b = _c getDir _rp;
    private _dir = _beg getDir _end;
    // running outwards: within ~50 degrees of radial, either way along it
    private _off = [_dir, _b] call _fnc_angDiff;
    if (_off > 50 && {_off < 130}) then {continue};
    if (_off >= 130) then {_dir = _dir + 180};
    _cands pushBack [abs (_d - (_ringR + 20)), _b, _rp, _dir % 360, _w max 4];
} forEach (_c nearRoads (_ringR + 100));
_cands sort true;
private _approaches = [];
{
    _x params ["", "_b", "_rp", "_dir", "_w"];
    if ((count _approaches) >= AIC_APPROACH_MAX) exitWith {};
    if ((_approaches findIf {([_x select 0, _b] call _fnc_angDiff) < AIC_APPROACH_GAP}) >= 0) then {continue};
    if ([_rp] call AIC_fnc_onRunway) then {continue};
    _approaches pushBack [_b, _rp, _dir, _w];
} forEach _cands;

// --- outposts: open high ground on the ring where no road comes in ------------------
private _outposts = [];
for "_b" from 0 to 315 step 45 do {
    private _p = _c getPos [_ringR * 0.85, _b];
    _p = [_p select 0, _p select 1, 0];
    private _q = [_p, (_ringR * 0.25) min 80, "hills + meadow - 2*houses - trees - 10*sea", 7] call AIC_fnc_bestPlace;
    if (_q isEqualTo [] && {!surfaceIsWater _p} && {!isOnRoad _p}
        && {(_p isFlatEmpty [4, -1, 0.4, 4, 0, false]) isNotEqualTo []}) then {_q = _p};
    if (_q isNotEqualTo [] && {!([_q] call AIC_fnc_onRunway)}) then {_outposts pushBack [_b, _q]};
};

_layout = createHashMapFromArray [
    ["radius", _r],
    ["builtR", _builtR],
    ["ringR", _ringR],
    ["large", _large],
    ["houses", _n],
    ["approaches", _approaches],
    ["outposts", _outposts]
];
_obj set ["layout", _layout];

["garrison: layout of '%1': %2 houses, built up to %3 m of %4, %5 approaches, %6 outposts%7", [
    _obj getOrDefault ["name", _obj getOrDefault ["id", ""]], _n, round _builtR, round _r,
    count _approaches, count _outposts, ["", " (held in posts)"] select _large
]] call AIC_fnc_log;

_layout
