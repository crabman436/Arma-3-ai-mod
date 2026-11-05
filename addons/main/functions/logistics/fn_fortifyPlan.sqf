/*
    Function: AIC_fnc_fortifyPlan

    Description:
        Lays out the fortification of one objective a commander holds
        (server; built step by step by AIC_fnc_fortifyCycle). The plan is
        fixed by the terrain (no randomness), so two sides planning the
        same place pick the same spots and reuse what stands there.

        Kind of place: an airfield (an airfield of AIC_fnc_airfields within
        the objective's radius + 600 m), a base (record "isBase"), or any
        other place (town, marker). Counts per kind:
                      roadblocks  MG nests  AT  AA  tower  service  net
            base          3          3       1   1    1       1      1
            airfield      2          3       1   2    1       1      1
            other         2          2       1   0    0       0      0
        (setting "fortifyRoadblocks" false: no roadblocks; setting
        "fortifyServicePoints" false: no service point.)

        Perimeter: a ring at 0.8 x radius (50..180 m, inside the 200 m a
        garrison mans guns in). Every 15 degrees a spot is tried (and 10 /
        20 m in or out); a spot is good when it is dry, not on a road or a
        runway / taxiway (AIC_fnc_onRunway), free of buildings, walls, fences,
        trees and rocks within 4 m, flat (isFlatEmpty gradient 0.3), with no
        vehicle, static or prop within 4 m and at least 8 m from every other
        planned spot. Spots are scored by height above the centre plus a
        bonus towards the threat; the best ones, at least 45 degrees apart,
        get the nests (HMG, GMG, HMG ... then AT, from
        AIC_fnc_staticClasses) facing outwards behind a sandbag wall (one
        long bag fence in front, two short ones at the sides), and the
        tower. The threat is the nearest known enemy contact or threat
        cluster, else the nearest objective another side holds, else the
        way away from the own HQ.

        Roadblocks: road segments (main road, road, track; no bridges or
        footpaths) crossing the band from 0.8 x ring to ring + 150 m, that
        run outwards (within ~50 degrees of radial), at least 50 degrees
        apart, the ones nearest ring + 30 m first. A roadblock narrows the
        road but leaves the lane open (vehicles of both sides still pass):
        two striped concrete barriers on the shoulders, staggered 6 m, two
        cones farther out, and an HMG nest beside the road facing outwards.

        AA (bases, airfields): open ground (AIC_fnc_bestPlace) inside half
        the ring, off the runway, behind sandbags. Service point (bases,
        airfields): fuel, vehicle ammunition and repair (the first class of
        each AIC_FORT_* list that exists, AIC_fnc_fortifyCycle refuels,
        rearms and repairs vehicles standing near it) in a row on open
        ground inside the ring; its position is the plan's "service".
        Camo net: over the vehicle park, placed when the park is laid out
        (item position "PARK").

    Parameters:
        0: HASHMAP - commander
        1: HASHMAP - objective record (owned by the commander's side)

    Returns:
        HASHMAP - "items" array of [kind, class, posATL, dir, role]
                  (kind "STATIC" - manned by the garrison, "PROP", "SERVICE",
                  "NET"), "service" (posATL or []), "kind" ("BASE",
                  "AIRFIELD", "OTHER"), "threatDir"

    Example:
        private _plan = [_cmd, _obj] call AIC_fnc_fortifyPlan;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]], ["_obj", createHashMap, [createHashMap]]];

private _side = _cmd getOrDefault ["side", sideUnknown];
private _c = _obj getOrDefault ["pos", []];
if (!(_c isEqualType []) || { count _c < 2 }) exitWith { createHashMapFromArray [["items", []], ["service", []], ["kind", "OTHER"], ["threatDir", 0]] };
_c = [_c select 0, _c select 1, 0];
private _r = _obj getOrDefault ["radius", 250];
if !(_r isEqualType 0) then { _r = 250; };
private _ring = ((_r * 0.8) min 180) max 50;

// ---------------------------------------------------------------- kind of place
private _fields = (call AIC_fnc_airfields) select { ((_x select 1) distance2D _c) < (_r + 600) };
private _kind = switch (true) do {
    case (_fields isNotEqualTo []): { "AIRFIELD" };
    case ((_obj getOrDefault ["isBase", false]) isEqualTo true): { "BASE" };
    default { "OTHER" };
};
private _counts = createHashMapFromArray [
    ["BASE",     [3, 3, 1, 1, 1, 1, 1]],
    ["AIRFIELD", [2, 3, 1, 2, 1, 1, 1]],
    ["OTHER",    [2, 2, 1, 0, 0, 0, 0]]
] get _kind;
_counts params ["_nRoad", "_nNest", "_nAT", "_nAA", "_nTower", "_nService", "_nNet"];
if !(([_cmd, "fortifyRoadblocks"] call AIC_fnc_getSetting) isEqualTo true) then { _nRoad = 0; };
if !(([_cmd, "fortifyServicePoints"] call AIC_fnc_getSetting) isEqualTo true) then { _nService = 0; };

// ---------------------------------------------------------------- runways and taxiways
private _fnc_onRunway = { params ["_p"]; [_p] call AIC_fnc_onRunway };

// ---------------------------------------------------------------- spot check
private _taken = [];
private _terrain = ["BUILDING", "HOUSE", "CHURCH", "CHAPEL", "FUELSTATION", "HOSPITAL", "RUIN", "BUNKER", "FORTRESS",
    "VIEW-TOWER", "LIGHTHOUSE", "WALL", "FENCE", "TREE", "ROCK", "ROCKS", "POWER LINES", "TRANSMITTER", "POWERSOLAR", "POWERWIND"];
private _fnc_spot = {
    params ["_p", ["_clear", 4], ["_onRoadOk", false]];
    !surfaceIsWater _p
    && { _onRoadOk || { !isOnRoad _p } }
    && { !([_p] call _fnc_onRunway) }
    && { (_taken findIf { (_x distance2D _p) < 8 }) < 0 }
    && { (nearestTerrainObjects [_p, _terrain, _clear, false, true]) isEqualTo [] }
    && { ((ATLToASL _p) isFlatEmpty [-1, -1, 0.3, 3, 0, false, objNull]) isNotEqualTo [] }
    && { ((nearestObjects [_p, ["AllVehicles", "Static", "Thing"], _clear]) findIf { !(_x isKindOf "CAManBase") }) < 0 }
};

// ---------------------------------------------------------------- threat direction
private _threatPos = [];
private _best = 1e9;
{
    private _p = _x getOrDefault ["pos", []];
    if (_p isEqualType [] && { count _p >= 2 } && { (_p distance2D _c) < _best }) then { _best = _p distance2D _c; _threatPos = _p; };
} forEach (((_cmd getOrDefault ["knownEnemies", []]) + (_cmd getOrDefault ["threats", []])) select { _x isEqualType createHashMap });
if (_threatPos isEqualTo []) then {
    {
        private _o = _x getOrDefault ["owner", sideUnknown];
        private _p = _x getOrDefault ["pos", []];
        if (_o isNotEqualTo _side && { _o isNotEqualTo sideUnknown } && { _p isEqualType [] } && { count _p >= 2 } && { (_p distance2D _c) < _best }) then {
            _best = _p distance2D _c; _threatPos = _p;
        };
    } forEach ((_cmd getOrDefault ["objectives", []]) select { _x isEqualType createHashMap });
};
private _threatDir = if (_threatPos isNotEqualTo []) then { _c getDir _threatPos } else {
    private _hq = _cmd getOrDefault ["hq", []];
    if (_hq isEqualType [] && { count _hq >= 2 } && { (_hq distance2D _c) > 50 }) then { _hq getDir _c } else { 0 }
};
private _fnc_angDiff = { params ["_a", "_b"]; abs (((_a - _b + 540) % 360) - 180) };

private _items = [];
private _fnc_add = { params ["_kind", "_cls", "_p", "_dir", ["_role", ""]]; _items pushBack [_kind, _cls, [_p select 0, _p select 1, 0], _dir % 360, _role]; };
// a sandbag wall in front of a gun (long) and at its sides (short)
private _fnc_sandbags = {
    params ["_p", "_dir"];
    ["PROP", "Land_BagFence_Long_F", _p getPos [1.8, _dir], _dir] call _fnc_add;
    ["PROP", "Land_BagFence_Short_F", _p getPos [1.5, _dir - 75], _dir - 75] call _fnc_add;
    ["PROP", "Land_BagFence_Short_F", _p getPos [1.5, _dir + 75], _dir + 75] call _fnc_add;
};
private _statics = [_cmd] call AIC_fnc_staticClasses;
private _fnc_gun = { params ["_role"]; private _l = _statics getOrDefault [_role, []]; if (_l isEqualTo []) then { "" } else { _l select 0 } };

// ---------------------------------------------------------------- perimeter spots
private _cands = [];
private _hC = getTerrainHeightASL _c;
for "_b" from 0 to 345 step 15 do {
    {
        private _p = _c getPos [_ring + _x, _b];
        _p = [_p select 0, _p select 1, 0];
        if ([_p] call _fnc_spot) exitWith {
            private _score = (getTerrainHeightASL _p) - _hC + 40 * cos ([_b, _threatDir] call _fnc_angDiff);
            _cands pushBack [_score, _b, _p];
        };
    } forEach [0, -10, 10, -20, 20];
};
_cands sort false;
private _chosen = [];
{
    _x params ["", "_b", "_p"];
    if ((_chosen findIf { ([_x select 0, _b] call _fnc_angDiff) < 45 }) < 0) then { _chosen pushBack [_b, _p]; };
    if ((count _chosen) >= (_nNest + _nAT + _nTower)) exitWith {};
} forEach _cands;

{
    _x params ["_b", "_p"];
    private _role = switch (true) do {
        case (_forEachIndex < _nNest): { ["HMG", "GMG"] select (_forEachIndex % 2) };
        case (_forEachIndex < (_nNest + _nAT)): { "AT" };
        default { "TOWER" };
    };
    _taken pushBack _p;
    if (_role isEqualTo "TOWER") then {
        ["PROP", AIC_FORT_TOWER, _p, _b + 180] call _fnc_add;
    } else {
        private _cls = [_role] call _fnc_gun;
        if (_role isEqualTo "GMG" && { _cls isEqualTo "" }) then { _cls = ["HMG"] call _fnc_gun; };
        if (_cls isNotEqualTo "") then {
            ["STATIC", _cls, _p, _b, _role] call _fnc_add;
            [_p, _b] call _fnc_sandbags;
        };
    };
} forEach _chosen;

// ---------------------------------------------------------------- roadblocks
if (_nRoad > 0) then {
    private _roads = (_c nearRoads (_ring + 150)) select {
        private _d = _x distance2D _c;
        _d >= (_ring * 0.8) && { _d <= (_ring + 150) }
    };
    private _rCands = [];
    {
        private _info = getRoadInfo _x;
        _info params ["_type", "_w", "_ped", "", "", "", "_beg", "_end", ["_bridge", false]];
        if (!(_type in ["MAIN ROAD", "ROAD", "TRACK"]) || { _ped } || { _bridge }) then { continue };
        private _rp = getPosATL _x;
        _rp = [_rp select 0, _rp select 1, 0];
        private _b = _c getDir _rp;
        private _d = _beg getDir _end;
        // running outwards: within ~50 degrees of radial (either way along it)
        private _off = [_d, _b] call _fnc_angDiff;
        if (_off > 50 && { _off < 130 }) then { continue };
        if (_off >= 130) then { _d = _d + 180; };
        _rCands pushBack [abs ((_rp distance2D _c) - (_ring + 30)), _b, _rp, _d, _w max 4];
    } forEach _roads;
    _rCands sort true;
    private _blocks = [];
    {
        _x params ["", "_b", "_rp", "_d", "_w"];
        if ((count _blocks) >= _nRoad) exitWith {};
        if ((_blocks findIf { ([_x, _b] call _fnc_angDiff) < 50 }) >= 0) then { continue };
        if ([_rp] call _fnc_onRunway) then { continue };
        _blocks pushBack _b;
        private _half = _w / 2 + 1.5;
        ["PROP", AIC_FORT_BARRIER, _rp getPos [_half, _d - 90], _d] call _fnc_add;
        ["PROP", AIC_FORT_BARRIER, (_rp getPos [6, _d]) getPos [_half, _d + 90], _d] call _fnc_add;
        ["PROP", "RoadCone_L_F", (_rp getPos [14, _d]) getPos [_w / 2, _d - 90], _d] call _fnc_add;
        ["PROP", "RoadCone_L_F", (_rp getPos [14, _d]) getPos [_w / 2, _d + 90], _d] call _fnc_add;
        // the gun beside the road, whichever side has room
        private _gunCls = ["HMG"] call _fnc_gun;
        if (_gunCls isNotEqualTo "") then {
            {
                private _gp = _rp getPos [_half + 5, _d + _x];
                _gp = [_gp select 0, _gp select 1, 0];
                if ([_gp, 3] call _fnc_spot) exitWith {
                    _taken pushBack _gp;
                    ["STATIC", _gunCls, _gp, _d, "HMG"] call _fnc_add;
                    [_gp, _d] call _fnc_sandbags;
                };
            } forEach [90, -90, 120, -120];
        };
    } forEach _rCands;
};

// ---------------------------------------------------------------- open ground inside
private _fnc_inside = {
    params ["_rad", ["_clear", 6]];
    private _p = [_c, _rad, "meadow - 3*houses - 2*forest - trees - 10*sea", 12] call AIC_fnc_bestPlace;
    if (_p isNotEqualTo [] && { [_p, _clear] call _fnc_spot }) exitWith { _p };
    // the engine's choice was blocked: a few fixed tries around the centre
    private _found = [];
    for "_b" from 0 to 330 step 30 do {
        {
            private _q = _c getPos [_x, _b];
            _q = [_q select 0, _q select 1, 0];
            if ([_q, _clear] call _fnc_spot) exitWith { _found = _q; };
        } forEach [_rad * 0.5, _rad * 0.8, _rad * 0.3];
        if (_found isNotEqualTo []) exitWith {};
    };
    _found
};

for "_i" from 1 to _nAA do {
    private _cls = ["AA"] call _fnc_gun;
    if (_cls isEqualTo "") exitWith {};
    private _p = [_ring * 0.5] call _fnc_inside;
    if (_p isEqualTo []) exitWith {};
    _taken pushBack _p;
    ["STATIC", _cls, _p, _threatDir, "AA"] call _fnc_add;
    [_p, _threatDir] call _fnc_sandbags;
};

private _service = [];
if (_nService > 0) then {
    private _p = [_ring * 0.6, 10] call _fnc_inside;
    if (_p isNotEqualTo []) then {
        _service = _p;
        _taken pushBack _p;
        private _dir = _c getDir _p;
        {
            _x params ["_list", "_k"];
            private _i = _list findIf { isClass (configFile >> "CfgVehicles" >> _x) };
            // in a row across the way in: left, middle, right, 8 m apart
            if (_i >= 0) then { ["SERVICE", _list select _i, _p getPos [8 * (abs (_forEachIndex - 1)), _dir + ([-90, 0, 90] select _forEachIndex)], _dir, _k] call _fnc_add; };
        } forEach [[AIC_FORT_FUEL, "FUEL"], [AIC_FORT_AMMO, "AMMO"], [AIC_FORT_REPAIR, "REPAIR"]];
    };
};

if (_nNet > 0) then {
    private _net = ["CamoNet_BLUFOR_big_F", "CamoNet_OPFOR_big_F", "CamoNet_INDP_big_F"] param [[west, east, independent] find _side, ""];
    if (_net isNotEqualTo "" && { isClass (configFile >> "CfgVehicles" >> _net) }) then { _items pushBack ["NET", _net, "PARK", 0, ""]; };
};

createHashMapFromArray [["items", _items], ["service", _service], ["kind", _kind], ["threatDir", _threatDir]]
