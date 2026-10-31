/*
 * Name: AIC_fnc_garrisonBuildings
 * Description:
 *   Hands out the defensive positions of an infantry group around a centre.
 *   Unscheduled and one-shot: units get their target (doMove / orderGetIn)
 *   and the unit variable "AIC_garrisonPos"; AIC_fnc_monitorGarrison settles
 *   them on later commander cycles once they arrive. Every unit on foot
 *   except players takes part, the leader last. In order:
 *     1. Static weapons. Empty, armed, unlocked static weapons in the radius
 *        (no mortars) are manned, by at most half of the group. The gunner
 *        keeps the unit variable "AIC_gunnerOf" (AIC_fnc_classifyGroup still
 *        counts him as infantry) and the gun "AIC_gunner".
 *     2. Sentries. A group of 4 or more posts one, of 7 or more two, at the
 *        edge of the place (0.6 to 1.15 radius out): the highest position of
 *        an edge building near the bearing, or a terrain post on high ground
 *        with trees (AIC_fnc_bestPlace) when there is no building. The
 *        bearings are the group's sector (its own slice of the place), the
 *        threat's side first when one is known. Sentries get the unit
 *        variable "AIC_sentry"; AIC_fnc_sentryWatch raises the alarm when
 *        one recognises an enemy.
 *     3. Buildings. Spread over the group's sector: buildings nearest the
 *        sector's anchor are filled with at most AIC_GARRISON_PER_BUILDING
 *        units each, and a building within 20 m of one already used is
 *        skipped while others remain, so one squad covers a street, not a
 *        single house. High positions and positions near the threat go
 *        first. A position is claimed through the building variable
 *        "AIC_claims" and the unit variable "AIC_buildingPos", so two groups
 *        in one town never take the same spot.
 *     4. Perimeter. Whoever is left (open ground, a full town) spreads on a
 *        ring around the centre, an arc towards the threat or the sector,
 *        next to a tree, rock or wall when one is close.
 *
 * Parameters:
 *   0: GROUP  - infantry group (must be local, the server commands it)
 *   1: ARRAY  - centre position
 *   2: NUMBER - (optional) search radius, default 150 (clamped to 30..200)
 *   3: ARRAY  - (optional) position of the nearest threat, default [] (none)
 *   4: BOOL   - (optional) man static weapons, default true
 *   5: NUMBER - (optional) the group's sector: bearing from the centre, -1
 *               for none (whole place), default -1
 *
 * Returns:
 *   NUMBER - number of units given a position
 *
 * Example:
 *   private _sent = [_group, _rec get "taskPos", 150, _threatPos, true, 90] call AIC_fnc_garrisonBuildings;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_group", grpNull, [grpNull]],
    ["_center", [], [[]]],
    ["_radius", 150, [0]],
    ["_threatPos", [], [[]]],
    ["_manStatics", true, [true]],
    ["_sector", -1, [0]]
];

if (isNull _group || {count _center < 2}) exitWith {0};
private _leader = leader _group;
if (isNull _leader) exitWith {0};
_radius = (_radius min 200) max 30;
private _c = [_center select 0, _center select 1, 0];
private _hasThreat = count _threatPos >= 2;
private _threatDir = if (_hasThreat) then {_c getDir _threatPos} else {_c getDir _leader};
private _hasSector = _sector >= 0;
private _facing = if (_hasSector) then {_sector} else {_threatDir};

// the leader comes last: he takes what is left
private _free = (units _group) select {
    alive _x && {_x != _leader} && {isNull objectParent _x} && {!isPlayer _x}
};
if (alive _leader && {isNull objectParent _leader} && {!isPlayer _leader}) then {_free pushBack _leader};
if (_free isEqualTo []) exitWith {0};
private _total = count _free;

// every enterable building of the place, with its free positions
private _buildings = (nearestObjects [_c, ["House", "Building"], _radius * 1.2, true]) select {alive _x};
private _fnc_freePositions = {
    params ["_b"];
    // claims of units that left or died have lapsed
    private _claims = (_b getVariable ["AIC_claims", []]) select {
        _x params ["_p", "_u"];
        alive _u && {(_u getVariable ["AIC_buildingPos", []]) isEqualTo _p}
    };
    _b setVariable ["AIC_claims", _claims];
    private _taken = _claims apply {_x select 0};
    (_b buildingPos -1) select {
        ((_x select 0) != 0 || {(_x select 1) != 0}) && {!(_x in _taken)}
    }
};
private _fnc_claim = {
    params ["_unit", "_b", "_bp", "_stance"];
    _unit doMove _bp;
    _unit setVariable ["AIC_garrisonPos", _bp];
    _unit setVariable ["AIC_buildingPos", _bp];
    _unit setVariable ["AIC_garrisonStance", _stance];
    private _claims = _b getVariable ["AIC_claims", []];
    _claims pushBack [_bp, _unit];
    _b setVariable ["AIC_claims", _claims];
};

// --- 1. static weapons ---------------------------------------------------------
private _guns = 0;
if (_manStatics) then {
    private _maxGuns = floor (_total / 2);
    {
        if (_guns >= _maxGuns) exitWith {};
        private _static = _x;
        private _owner = _static getVariable ["AIC_gunner", objNull];
        if (
            alive _static
            && {isNull (gunner _static)}
            && {(locked _static) != 2}
            && {getNumber (configOf _static >> "artilleryScanner") != 1}
            && {((magazinesAllTurrets _static) findIf {(_x select 2) > 0}) >= 0}
            && {!alive _owner || {(_owner getVariable ["AIC_gunnerOf", objNull]) isNotEqualTo _static}}
        ) then {
            private _unit = _free deleteAt 0;
            _unit assignAsGunner _static;
            [_unit] allowGetIn true;
            [_unit] orderGetIn true;
            _unit setVariable ["AIC_gunnerOf", _static];
            _unit setVariable ["AIC_garrisonPos", getPosATL _static];
            _static setVariable ["AIC_gunner", _unit];
            _guns = _guns + 1;
        };
    } forEach (nearestObjects [_c, ["StaticWeapon"], _radius]);
};

// --- 2. sentries at the edge ---------------------------------------------------
private _sentries = 0;
private _wanted = switch (true) do {
    case (count _free >= 7): {2};
    case (count _free >= 4): {1};
    default {0};
};
if (_wanted > 0) then {
    private _bearings = if (_wanted == 1) then {[_facing]} else {[_facing - 35, _facing + 35]};
    if (_hasThreat && {_hasSector}) then {_bearings set [0, _threatDir]};
    private _edge = _buildings select {
        private _d = _x distance2D _c;
        _d >= (_radius * 0.6) && {_d <= (_radius * 1.15)}
    };
    {
        if (_free isEqualTo []) exitWith {};
        private _bearing = _x;
        private _post = _c getPos [_radius * 0.85, _bearing];
        private _unit = _free deleteAt 0;
        _unit setVariable ["AIC_sentry", true];

        // the edge building nearest the post with a free position: its highest one
        private _best = objNull;
        private _bestD = 80;
        {
            private _d = _x distance2D _post;
            if (_d < _bestD && {([_x] call _fnc_freePositions) isNotEqualTo []}) then {_bestD = _d; _best = _x};
        } forEach _edge;
        if (!isNull _best) then {
            private _bps = [_best] call _fnc_freePositions;
            private _high = _bps select 0;
            {if ((_x select 2) > (_high select 2)) then {_high = _x}} forEach _bps;
            [_unit, _best, _high, "UP"] call _fnc_claim;
        } else {
            // no building out there: a terrain post on high ground with trees
            private _p = [_post, 60, "hills + trees - 10*sea"] call AIC_fnc_bestPlace;
            if (_p isEqualTo []) then {_p = if (surfaceIsWater _post) then {_c} else {[_post select 0, _post select 1, 0]}};
            _unit doMove _p;
            _unit setVariable ["AIC_garrisonPos", _p];
            _unit setVariable ["AIC_garrisonStance", "MIDDLE"];
        };
        _sentries = _sentries + 1;
    } forEach _bearings;
};

// --- 3. buildings, spread over the sector --------------------------------------
// the anchor: the sector's middle, else the threatened edge, else the centre
private _anchor = switch (true) do {
    case (_hasSector): {_c getPos [_radius * 0.35, _sector]};
    case (_hasThreat): {_c getPos [_radius * 0.35, _threatDir]};
    default {_c};
};
private _order = [];
{ _order pushBack [_x distance2D _anchor, _forEachIndex]; } forEach _buildings;
_order sort true;

private _inside = 0;
private _used = [];
// two passes: first only buildings well apart from each other, then the rest
{
    private _pass = _x;
    {
        if (_free isEqualTo []) exitWith {};
        private _b = _buildings select (_x select 1);
        if (_b in _used) then {continue};
        if (_pass == 0 && {(_used findIf {(_x distance2D _b) < 20}) >= 0}) then {continue};
        private _bps = [_b] call _fnc_freePositions;
        if (_bps isEqualTo []) then {continue};

        // high up first; 10 m closer to the threat is worth one metre of height
        private _rank = [];
        {
            _rank pushBack [(if (_hasThreat) then {(_x distance2D _threatPos) / 10} else {0}) - (_x select 2) + random 1, _forEachIndex];
        } forEach _bps;
        _rank sort true;
        for "_i" from 0 to (((count _rank) min AIC_GARRISON_PER_BUILDING) - 1) do {
            if (_free isEqualTo []) exitWith {};
            [_free deleteAt 0, _b, _bps select ((_rank select _i) select 1), "UP"] call _fnc_claim;
            _inside = _inside + 1;
        };
        _used pushBack _b;
    } forEach _order;
    if (_free isEqualTo []) exitWith {};
} forEach [0, 1];

// --- 4. perimeter --------------------------------------------------------------
private _ring = count _free;
if (_ring > 0) then {
    private _arc = [360, 200] select (_hasThreat || _hasSector);
    private _ringR = ((15 + 3 * _ring) min 45) + random 10;
    // groups on the same ground do not share one ring
    private _start = _facing - _arc / 2 + random 20;
    {
        private _dir = _start + _arc * (_forEachIndex + 0.5) / _ring;
        private _p = _c getPos [_ringR, _dir];
        private _cover = nearestTerrainObjects [_p, ["TREE", "SMALL TREE", "BUSH", "ROCK", "ROCKS", "WALL", "FENCE"], 8, true];
        // just behind the cover, seen from the outside
        if (_cover isNotEqualTo []) then {_p = (getPosATL (_cover select 0)) getPos [1.5, _dir + 180]};
        if (surfaceIsWater _p) then {_p = _c};
        _p = [_p select 0, _p select 1, 0];
        _x doMove _p;
        _x setVariable ["AIC_garrisonPos", _p];
        _x setVariable ["AIC_garrisonStance", "MIDDLE"];
    } forEach _free;
};

["garrison: group %1 takes position%2: %3 in buildings, %4 sentries, %5 on static weapons, %6 on the perimeter", [
    groupId _group, if (_hasSector) then {format [" (sector %1)", round _sector]} else {""}, _inside, _sentries, _guns, _ring
]] call AIC_fnc_log;

_total
