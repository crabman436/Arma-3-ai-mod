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
 *     2. Buildings. The buildings closest to the threatened side of the
 *        centre (the centre itself without a threat) are filled with up to
 *        4 units each, so teams can cover each other instead of one man
 *        sitting alone per house. High positions and positions near the
 *        threat go first. A position is claimed through the building
 *        variable "AIC_claims" and the unit variable "AIC_buildingPos", so
 *        two groups in one town never take the same spot.
 *     3. Perimeter. Whoever is left (open ground, a full town) spreads on a
 *        ring around the centre, an arc towards the threat if there is one,
 *        next to a tree, rock or wall when one is close.
 *
 * Parameters:
 *   0: GROUP  - infantry group (must be local, the server commands it)
 *   1: ARRAY  - centre position
 *   2: NUMBER - (optional) search radius, default 150 (clamped to 30..200)
 *   3: ARRAY  - (optional) position of the nearest threat, default [] (none)
 *   4: BOOL   - (optional) man static weapons, default true
 *
 * Returns:
 *   NUMBER - number of units given a position
 *
 * Example:
 *   private _sent = [_group, _rec get "taskPos", 150, _threatPos] call AIC_fnc_garrisonBuildings;
 */

params [
    ["_group", grpNull, [grpNull]],
    ["_center", [], [[]]],
    ["_radius", 150, [0]],
    ["_threatPos", [], [[]]],
    ["_manStatics", true, [true]]
];

if (isNull _group || {count _center < 2}) exitWith {0};
private _leader = leader _group;
if (isNull _leader) exitWith {0};
_radius = (_radius min 200) max 30;
private _c = [_center select 0, _center select 1, 0];
private _hasThreat = count _threatPos >= 2;
private _threatDir = if (_hasThreat) then {_c getDir _threatPos} else {_c getDir _leader};

// the leader comes last: he takes what is left
private _free = (units _group) select {
    alive _x && {_x != _leader} && {isNull objectParent _x} && {!isPlayer _x}
};
if (alive _leader && {isNull objectParent _leader} && {!isPlayer _leader}) then {_free pushBack _leader};
if (_free isEqualTo []) exitWith {0};
private _total = count _free;

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

// --- 2. buildings --------------------------------------------------------------
// the threatened edge of the town, not its middle
private _anchor = if (_hasThreat) then {_c getPos [_radius * 0.35, _threatDir]} else {_c};
private _buildings = (nearestObjects [_c, ["House", "Building"], _radius, true]) select {alive _x};
private _order = [];
{ _order pushBack [_x distance2D _anchor, _forEachIndex]; } forEach _buildings;
_order sort true;

private _inside = 0;
{
    if (_free isEqualTo []) exitWith {};
    private _b = _buildings select (_x select 1);

    // claims of units that left or died have lapsed
    private _claims = (_b getVariable ["AIC_claims", []]) select {
        _x params ["_p", "_u"];
        alive _u && {(_u getVariable ["AIC_buildingPos", []]) isEqualTo _p}
    };
    private _taken = _claims apply {_x select 0};
    private _bps = (_b buildingPos -1) select {
        ((_x select 0) != 0 || {(_x select 1) != 0}) && {!(_x in _taken)}
    };

    if (_bps isNotEqualTo []) then {
        // high up first; 10 m closer to the threat is worth one metre of height
        private _rank = [];
        {
            _rank pushBack [(if (_hasThreat) then {(_x distance2D _threatPos) / 10} else {0}) - (_x select 2) + random 1, _forEachIndex];
        } forEach _bps;
        _rank sort true;
        for "_i" from 0 to (((count _rank) min 4) - 1) do {
            if (_free isEqualTo []) exitWith {};
            private _bp = _bps select ((_rank select _i) select 1);
            private _unit = _free deleteAt 0;
            _unit doMove _bp;
            _unit setVariable ["AIC_garrisonPos", _bp];
            _unit setVariable ["AIC_buildingPos", _bp];
            _unit setVariable ["AIC_garrisonStance", "UP"];
            _claims pushBack [_bp, _unit];
            _inside = _inside + 1;
        };
    };
    _b setVariable ["AIC_claims", _claims];
} forEach _order;

// --- 3. perimeter --------------------------------------------------------------
private _ring = count _free;
if (_ring > 0) then {
    private _arc = [360, 200] select _hasThreat;
    private _ringR = ((15 + 3 * _ring) min 45) + random 10;
    // groups on the same ground do not share one ring
    private _start = _threatDir - _arc / 2 + random 20;
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

["garrison: group %1 takes position: %2 in buildings, %3 on static weapons, %4 on the perimeter", [
    groupId _group, _inside, _guns, _ring
]] call AIC_fnc_log;

_total
