/*
 * Name: AIC_fnc_orderAssault
 * Description:
 *   Orders one ground group as part of an assault (AIC_fnc_assaultFor). Every
 *   group gets a place of its own, so the assault comes in on a broad front
 *   and not as a crowd on one line: AIC_ASSAULT_AXIS_LANES lanes side by side
 *   on an approach, then a second approach 70 degrees to one side, a third to
 *   the other, then further rows behind (records "assaultLane", "assaultAxis",
 *   "assaultRow").
 *   State "STAGE": move to its place near the assembly area and hold, vehicles
 *   120 m behind the infantry (record "staged", "stagePos"). On a long march
 *   a waypoint to the side keeps groups from one base off one line.
 *   State "GO":
 *     INF          : to its line of departure, then seek and destroy at a
 *                    walk (speed LIMITED), COMBAT, in line. A flanking team
 *                    uses its flanking point as line of departure.
 *     Vehicles     : built-up objective with infantry in the assault: to an
 *                    overwatch position outside the town, on high ground
 *                    with a terrain line of sight to it when there is any
 *                    within 150 m, and hold there, firing in support
 *                    (record "overwatch"). Open ground, or
 *                    no infantry: to the line of departure, then seek and
 *                    destroy at a walk, so they do not race ahead.
 *
 * Parameters:
 *   0: GROUP   - group
 *   1: ARRAY   - objective position
 *   2: NUMBER  - objective radius
 *   3: STRING  - group type: "INF", "MOTOR", "MECH" or "ARMOR"
 *   4: ARRAY   - flanking point, [] for none
 *   5: HASHMAP - the assault
 *   6: HASHMAP - the group record
 *
 * Returns:
 *   BOOL - true if the order was applied
 *
 * Example:
 *   [_group, _pos, 300, "INF", [], _assault, _record] call AIC_fnc_orderAssault;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_radius", 300, [0]],
    ["_type", "INF", [""]],
    ["_via", [], [[]]],
    ["_assault", createHashMap, [createHashMap]],
    ["_record", createHashMap, [createHashMap]]
];

if (isNull _group || {count _pos < 2} || {count _assault == 0}) exitWith {false};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {false};

private _target = [_pos select 0, _pos select 1, 0];
private _isInf = _type isEqualTo "INF";
private _formation = ["WEDGE", "STAG COLUMN"] select _isInf;

// a place of its own: lanes side by side on an approach, then the next
// approach, then a second row behind the first
if ((_record getOrDefault ["assaultId", ""]) isNotEqualTo (_assault get "key")) then {
    private _n = _assault get "slots";
    _assault set ["slots", _n + 1];
    _record set ["assaultId", _assault get "key"];
    _record set ["assaultLane", (_n % AIC_ASSAULT_AXIS_LANES) - floor (AIC_ASSAULT_AXIS_LANES / 2)];
    _record set ["assaultAxis", (floor (_n / AIC_ASSAULT_AXIS_LANES)) % 3];
    _record set ["assaultRow", floor (_n / (3 * AIC_ASSAULT_AXIS_LANES))];
};
private _lane = _record get "assaultLane";
private _row = _record get "assaultRow";

// its approach, if that does not end in the water
private _stage = _assault get "stage";
private _stageDist = if (_stage isEqualTo []) then {0} else {_target distance2D _stage};
private _dir = (_assault get "dir") + ([0, 70, -70] select (_record get "assaultAxis"));
if (_stage isNotEqualTo [] && {surfaceIsWater (_target getPos [_stageDist, _dir])}) then {_dir = _assault get "dir"};

[_group] call AIC_fnc_clearWaypoints;
_group allowFleeing 0;
_group setBehaviour "AWARE";
_group setCombatMode "YELLOW";
_group setSpeedMode "NORMAL";

// a dry spot: the point itself, else the same distance from the target swung
// around in 15 degree steps, else the fallback (never the town itself for a
// place outside it)
private _fnc_dry = {
    params ["_p", ["_fallback", _target]];
    private _d = _target distance2D _p;
    private _b = _target getDir _p;
    private _found = _fallback;
    {
        private _q = _target getPos [_d, _b + _x];
        if (!surfaceIsWater _q) exitWith {_found = [_q select 0, _q select 1, 0]};
    } forEach [0, 15, -15, 30, -30, 45, -45, 60, -60];
    _found
};
private _fnc_wp = {
    params ["_p", "_wpType", "_beh", "_speed", "_form", "_done"];
    private _wp = _group addWaypoint [_p, 0];
    _wp setWaypointType _wpType;
    _wp setWaypointBehaviour _beh;
    _wp setWaypointCombatMode (["YELLOW", "RED"] select (_wpType isEqualTo "SAD"));
    _wp setWaypointSpeed _speed;
    _wp setWaypointFormation _form;
    _wp setWaypointCompletionRadius _done;
    _wp
};

// --- gather ------------------------------------------------------------------
if ((_assault get "state") isEqualTo "STAGE") exitWith {
    private _p = (_target getPos [_stageDist + _row * 150, _dir]) getPos [_lane * AIC_ASSAULT_FRONT, _dir + 90];
    if !(_isInf) then {
        _p = _p getPos [120, _dir];
        _p = [[_p select 0, _p select 1, 0], 100] call AIC_fnc_roadPos;
    };
    // (a lane in the water: somewhere dry near it, else the assembly area itself)
    _p = [_p, [_stage, _target] select (_stage isEqualTo [])] call _fnc_dry;
    // groups from one base do not march up one line: each goes its own way
    private _from = getPosATL _leader;
    private _way = _from distance2D _p;
    private _first = [];
    if (_way > 800) then {
        private _mid = (_from getPos [_way * 0.5, _from getDir _p]) getPos [(_lane * 200) + (random 100) - 50, (_from getDir _p) + 90];
        if (!surfaceIsWater _mid) then {
            _first = [[_mid select 0, _mid select 1, 0], "MOVE", "AWARE", "NORMAL", _formation, 60] call _fnc_wp;
        };
    };
    private _wp = [_p, "MOVE", "AWARE", "NORMAL", _formation, 40] call _fnc_wp;
    [_p, "HOLD", "AWARE", "NORMAL", ["WEDGE", "LINE"] select _isInf, 40] call _fnc_wp;
    _group setCurrentWaypoint ([_first, _wp] select (_first isEqualTo []));
    _record set ["staged", true];
    _record set ["stagePos", _p];
    true
};

_record set ["staged", false];
private _lanePos = {
    params ["_dist", "_spread", ["_fallback", _target]];
    [_target getPos [_dist, _dir + (_lane * _spread)], _fallback] call _fnc_dry
};

// --- vehicles watch over a built-up objective from outside --------------------
if (!_isInf && {_assault get "urban"} && {_assault get "hasInf"}) exitWith {
    // never into the town: a wet overwatch spot falls back to the assembly area
    private _p = [_radius + AIC_ASSAULT_OVERWATCH, 20, [_stage, _target getPos [_radius + AIC_ASSAULT_OVERWATCH, _assault get "dir"]] select (_stage isEqualTo [])] call _lanePos;
    // high ground near it that can actually see the town (terrain line of sight, 2 m up)
    private _eyeTarget = (AGLToASL _target) vectorAdd [0, 0, 2];
    {
        _x params ["_spot", "_score"];
        if (_score <= 0) exitWith {};
        private _q = [_spot select 0, _spot select 1, 0];
        if (!surfaceIsWater _q && {!terrainIntersectASL [(AGLToASL _q) vectorAdd [0, 0, 2], _eyeTarget]}) exitWith {_p = _q};
    } forEach (selectBestPlaces [_p, 150, "hills - forest - trees - houses - 10*sea", 15, 6]);
    private _wp = [_p, "MOVE", "AWARE", "LIMITED", "WEDGE", 40] call _fnc_wp;
    [_p, "HOLD", "AWARE", "LIMITED", "WEDGE", 40] call _fnc_wp;
    _group setCurrentWaypoint _wp;
    _record set ["overwatch", true];
    true
};

// --- in at a walk, on a broad front --------------------------------------------
private _start = if (count _via >= 2) then {[_via] call _fnc_dry} else {[_radius + 150 + (([50, 0] select _isInf)), 20] call _lanePos};
private _first = [];
if (count _via >= 2 || {(_leader distance2D _target) > (_radius + 200)}) then {
    _first = [_start, "MOVE", "AWARE", "NORMAL", "WEDGE", ([40, 25] select _isInf)] call _fnc_wp;
};
private _wpS = [[_radius * 0.45, 40] call _lanePos, "SAD", "COMBAT", "LIMITED", ["WEDGE", "LINE"] select _isInf, (_radius * 0.5) max 30] call _fnc_wp;
_group setCurrentWaypoint ([_first, _wpS] select (_first isEqualTo []));

true
