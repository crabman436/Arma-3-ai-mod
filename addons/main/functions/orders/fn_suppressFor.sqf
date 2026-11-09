/*
 * Name: AIC_fnc_suppressFor
 * Description:
 *   Support by fire that fires: while an assault is in GO, the groups on
 *   overwatch (role "SBF", or vehicles watching over a town, record
 *   "overwatch") put suppressive fire on the defenders instead of waiting
 *   for a target to show itself (server only, setting "suppressiveFire").
 *   Called by AIC_fnc_assaultCycle every cycle for every assault in GO.
 *
 *   Targets, in this order:
 *     - the commander's known enemy contacts ("knownEnemies") seen within
 *       AIC_SUPPRESS_FRESH s and inside the objective radius + 50 m: the
 *       contact's position and the positions of its known men and vehicles
 *       (no more than 3 a contact); the suppressing units are given
 *       positions, never the objects, so the gunners fire at where the
 *       enemy was last seen, not at what the commander happens to know;
 *     - with no fresh contact, during the first AIC_SUPPRESS_OPENING s of GO
 *       only: the edge of the objective facing the assault (the buildings
 *       there if any), so the overwatch opens up as the infantry steps off
 *       and does not sit silent while the town is quiet.
 *   Safety: a target with a friendly man or vehicle (own side or an allied
 *   one, players included) within AIC_SUPPRESS_SAFE m is dropped; a
 *   shooter does not fire on a target when a friendly stands within
 *   AIC_SUPPRESS_LINE m of the line between them (friendlies within 30 m of
 *   the shooter, its own group, do not count).
 *   Shooters: every armed vehicle of the group itself (AIC_fnc_vehicleWeapons;
 *   measured: the order given to a vehicle's gunner fires nothing, given to
 *   the vehicle it fires), and on foot every man of the group (an infantry
 *   SBF team is the machine-gun team). Targets go round the
 *   shooters in turn, so a team spreads its fire over the known positions.
 *   The jobs are written to the group variable "AIC_suppress" =
 *   [[[unit, positionASL], ...], untilTime]; AIC_fnc_suppressWatch (spawned
 *   once per group, flag "AIC_suppressWatch") re-issues doSuppressiveFire
 *   every AIC_SUPPRESS_PERIOD s until the time is up (AIC_SUPPRESS_HOLD s
 *   after the last refresh here, so the fire stops within a cycle of the
 *   assault ending) or a new order clears the variable
 *   (AIC_fnc_clearWaypoints, so a group sent in stops suppressing at once).
 *   Groups with a player and groups that are not on their overwatch spot
 *   yet (leader farther than 60 m from the HOLD waypoint, still driving up)
 *   are left alone.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: HASHMAP - assault record (AIC_fnc_assaultFor)
 *   2: ARRAY   - group records of the assault's members on ATTACK
 *   3: HASHMAP - the objective record
 *
 * Returns:
 *   NUMBER - groups given suppression jobs this call
 *
 * Example:
 *   [_cmd, _assault, _attacking, _obj] call AIC_fnc_suppressFor;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_assault", createHashMap, [createHashMap]],
    ["_attacking", [], [[]]],
    ["_obj", createHashMap, [createHashMap]]
];

if (!isServer || {count _cmd == 0} || {count _assault == 0}) exitWith {0};
if !(([_cmd, "suppressiveFire"] call AIC_fnc_getSetting) isEqualTo true) exitWith {0};

private _side = _cmd getOrDefault ["side", sideUnknown];
private _tPos = _assault getOrDefault ["pos", []];
if (!(_tPos isEqualType []) || {count _tPos < 2}) exitWith {0};
_tPos = [_tPos select 0, _tPos select 1, 0];
private _radius = _obj getOrDefault ["radius", 150];
if (!(_radius isEqualType 0) || {_radius <= 0}) then {_radius = 150};
private _roles = _assault getOrDefault ["roles", createHashMap];
if !(_roles isEqualType createHashMap) then {_roles = createHashMap};

// the groups on overwatch, in place, without players
private _sbf = _attacking select {
    _x isEqualType createHashMap
    && {(_x getOrDefault ["overwatch", false]) isEqualTo true}
    && {
        private _g = _x getOrDefault ["group", grpNull];
        !isNull _g && {alive leader _g} && {((units _g) findIf {isPlayer _x}) < 0}
        && {
            // on its spot: at the HOLD waypoint (the last one), not still on the way
            private _wps = waypoints _g;
            _wps isEqualTo [] || {((leader _g) distance2D (waypointPosition (_wps select ((count _wps) - 1)))) < 60}
        }
    }
};
if (_sbf isEqualTo []) exitWith {0};

// --- friendlies near the objective: the assault, players, allies -------------
private _fnc_friendlySide = {
    params ["_s"];
    (_side getFriend _s) >= AIC_HOSTILE_FRIEND && {_s != civilian || {_side == civilian}}
};
private _friendlies = (_tPos nearEntities [["CAManBase", "LandVehicle"], _radius + 300]) select {
    alive _x && {
        if (_x isKindOf "CAManBase") then {[side group _x] call _fnc_friendlySide}
        else {((crew _x) findIf {alive _x && {[side group _x] call _fnc_friendlySide}}) >= 0}
    }
};
private _friendlyPos = _friendlies apply {getPosATL _x};

// --- targets: fresh contacts inside the place ------------------------------------
private _targets = [];
private _contacts = _cmd getOrDefault ["knownEnemies", []];
if !(_contacts isEqualType []) then {_contacts = []};
{
    if !(_x isEqualType createHashMap) then {continue};
    if ((time - (_x getOrDefault ["lastSeen", -1e6])) > AIC_SUPPRESS_FRESH) then {continue};
    private _cPos = _x getOrDefault ["pos", []];
    if (!(_cPos isEqualType []) || {count _cPos < 2}) then {continue};
    if ((_cPos distance2D _tPos) > (_radius + 50)) then {continue};
    _targets pushBack (AGLToASL [_cPos select 0, _cPos select 1, 1.2]);
    private _n = 0;
    {
        if (_n >= 3) exitWith {};
        if (!isNull _x && {alive _x} && {(_x distance2D _tPos) <= (_radius + 50)}) then {
            // (a man in a vehicle: the vehicle)
            private _o = [_x, vehicle _x] select (_x isKindOf "CAManBase");
            _targets pushBack ((getPosASL _o) vectorAdd [0, 0, 0.8]);
            _n = _n + 1;
        };
    } forEach (_x getOrDefault ["known", []]);
} forEach _contacts;

// --- nothing seen yet: the near edge of the place as the assault steps off --------
private _goTime = _assault getOrDefault ["goTime", _assault getOrDefault ["time", time]];
if !(_goTime isEqualType 0) then {_goTime = time};
if (_targets isEqualTo [] && {(time - _goTime) <= AIC_SUPPRESS_OPENING}) then {
    private _dir = _assault getOrDefault ["dir", 0];
    if !(_dir isEqualType 0) then {_dir = 0};
    {
        private _edge = _tPos getPos [_radius * 0.8, _dir + _x];
        if (surfaceIsWater _edge) then {continue};
        private _houses = nearestObjects [_edge, ["House", "Building"], 60];
        private _p = if (_houses isEqualTo []) then {[_edge select 0, _edge select 1, 1.2]}
            else {private _h = getPosATL (_houses select 0); [_h select 0, _h select 1, 1.5]};
        _targets pushBack (AGLToASL _p);
    } forEach [0, -25, 25];
};
if (_targets isEqualTo []) exitWith {0};

// no fire where our own men are
_targets = _targets select {
    private _t = ASLToAGL _x;
    (_friendlyPos findIf {(_x distance2D _t) < AIC_SUPPRESS_SAFE}) < 0
};
if (_targets isEqualTo []) exitWith {0};

// a friendly on the line of fire (2D distance from the segment shooter -> target)
private _fnc_lineClear = {
    params ["_s", "_t"];
    private _v = [(_t select 0) - (_s select 0), (_t select 1) - (_s select 1)];
    private _len2 = (_v select 0) ^ 2 + (_v select 1) ^ 2;
    if (_len2 < 1) exitWith {true};
    (_friendlyPos findIf {
        private _f = _x;
        if ((_f distance2D _s) < 30) then {false} else {
            private _w = [(_f select 0) - (_s select 0), (_f select 1) - (_s select 1)];
            private _k = ((((_w select 0) * (_v select 0)) + ((_w select 1) * (_v select 1))) / _len2) max 0 min 1;
            private _c = [(_s select 0) + (_k * (_v select 0)), (_s select 1) + (_k * (_v select 1))];
            (_c distance2D [_f select 0, _f select 1]) < AIC_SUPPRESS_LINE
        }
    }) < 0
};

private _given = 0;
{
    private _rec = _x;
    private _g = _rec get "group";
    // the shooters: the armed vehicles themselves, every man on foot
    private _shooters = [];
    private _vehsSeen = [];
    {
        private _u = _x;
        if (!alive _u) then {continue};
        private _v = objectParent _u;
        if (isNull _v) then {_shooters pushBack _u; continue};
        if (_v in _vehsSeen) then {continue};
        _vehsSeen pushBack _v;
        if (([_v] call AIC_fnc_vehicleWeapons) isEqualTo []) then {continue};
        if (((crew _v) findIf {isPlayer _x}) >= 0) then {continue};
        _shooters pushBack _v;
    } forEach (units _g);
    if (_shooters isEqualTo []) then {continue};

    private _jobs = [];
    private _i = 0;
    {
        private _u = _x;
        private _sPos = getPosATL _u;
        // the next target this shooter may fire on, round robin
        private _picked = [];
        for "_k" from 0 to ((count _targets) - 1) do {
            private _t = _targets select ((_i + _k) mod (count _targets));
            if ([_sPos, ASLToAGL _t] call _fnc_lineClear) exitWith {_picked = _t};
        };
        _i = _i + 1;
        if (_picked isNotEqualTo []) then {_jobs pushBack [_u, _picked]};
    } forEach _shooters;
    if (_jobs isEqualTo []) then {continue};

    _g setVariable ["AIC_suppress", [_jobs, time + AIC_SUPPRESS_HOLD]];
    if !(_g getVariable ["AIC_suppressWatch", false]) then {
        _g setVariable ["AIC_suppressWatch", true];
        [_g] spawn AIC_fnc_suppressWatch;
        ["%1: %2 (%3) suppresses '%4' from overwatch: %5 shooters, %6 targets", [
            _side, groupId _g, _roles getOrDefault [hashValue _g, "overwatch"], _assault getOrDefault ["id", ""], count _jobs, count _targets
        ]] call AIC_fnc_log;
    };
    _given = _given + 1;
} forEach _sbf;

_given
