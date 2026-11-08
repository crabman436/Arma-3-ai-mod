/*
 * Name: AIC_fnc_rallySpot
 * Description:
 *   Where a broken group gathers before it is taken home (setting
 *   "recoverBroken"; AIC_fnc_updateGroups orders the retreat,
 *   AIC_fnc_recoverCycle takes it from there). A held place behind the
 *   group (AIC_fnc_rallyPoint) within AIC_RALLY_SPOT_NEAR is the spot:
 *   it is safe and has a garrison. Otherwise a spot of its own about
 *   AIC_RALLY_SPOT_DIST m away from the threat: cover (forest, trees,
 *   high ground, no houses; AIC_fnc_bestPlace within 300 m of the ideal
 *   point), dry, with no known threat within AIC_RALLY_SPOT_CLEAR m; the
 *   bearing is turned 45 degrees either way when the first try is no
 *   good, then the ideal point itself. Without a threat known the group
 *   goes away from the nearest enemy objective, else towards the HQ.
 *   The base the group is taken home to is the nearest held base to the
 *   spot (AIC_fnc_nearestBase), "" when the side holds none.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - the broken group
 *   2: ARRAY   - (optional) threat position to get away from, default []
 *
 * Returns:
 *   ARRAY - [spot [x, y, 0], base objective id or "", rally objective id
 *           or "" (a held place that is the spot)]
 *
 * Example:
 *   ([_cmd, _grp, _threat] call AIC_fnc_rallySpot) params ["_spot", "_base", "_place"];
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_threat", [], [[]]]
];

if (count _cmd == 0 || {isNull _group}) exitWith {[]};
private _leader = leader _group;
if (isNull _leader || {!alive _leader}) exitWith {[]};
private _lPos = getPosATL _leader;
_lPos = [_lPos select 0, _lPos select 1, 0];
private _rec = (_cmd getOrDefault ["groupData", createHashMap]) getOrDefault [hashValue _group, createHashMap];

// --- a held place behind, near enough: the spot ------------------------------------
private _rally = [_cmd, _group, _threat] call AIC_fnc_rallyPoint;
private _rallyObj = _rec getOrDefault ["rallyObj", ""];
if (!(_rallyObj isEqualType "") || {(_rec getOrDefault ["rallyHq", false]) isEqualTo true}) then {_rallyObj = ""};
if (_rally isNotEqualTo [] && {_rallyObj isNotEqualTo ""} && {(_rally distance2D _lPos) <= AIC_RALLY_SPOT_NEAR}) exitWith {
    private _base = [_cmd, _rally] call AIC_fnc_nearestBase;
    [[_rally select 0, _rally select 1, 0], _base, _rallyObj]
};
// (a rally point this far is no use to a broken squad on foot; its record is cleared)
_rec set ["rallyObj", ""];
_rec set ["rallyHq", false];

// --- a spot of its own, a kilometre from the threat --------------------------------------
private _side = _cmd getOrDefault ["side", sideUnknown];
private _from = _threat;
if (_from isEqualTo []) then {
    // away from the nearest enemy objective, else towards the HQ
    private _best = 1e9;
    {
        private _o = _x getOrDefault ["owner", sideUnknown];
        private _p = _x getOrDefault ["pos", []];
        if (_o isNotEqualTo _side && {_o isNotEqualTo sideUnknown} && {_p isEqualType []} && {count _p >= 2} && {(_p distance2D _lPos) < _best}) then {
            _best = _p distance2D _lPos; _from = _p;
        };
    } forEach ((_cmd getOrDefault ["objectives", []]) select {_x isEqualType createHashMap});
};
private _dir = if (_from isNotEqualTo []) then {
    _from getDir _lPos
} else {
    private _hq = _cmd getOrDefault ["hq", []];
    if (_hq isEqualType [] && {count _hq >= 2}) then {_lPos getDir _hq} else {random 360}
};

private _spot = [];
{
    private _ideal = _lPos getPos [AIC_RALLY_SPOT_DIST, _dir + _x];
    _ideal = [_ideal select 0, _ideal select 1, 0];
    private _p = [_ideal, 300, "forest + 2*trees + hills - 3*houses - 10*sea"] call AIC_fnc_bestPlace;
    if (_p isEqualTo [] && {!surfaceIsWater _ideal}) then {_p = _ideal};
    if (_p isNotEqualTo [] && {([_cmd, _p, AIC_RALLY_SPOT_CLEAR] call AIC_fnc_nearestThreat) isEqualTo []}) exitWith {_spot = _p};
} forEach [0, 45, -45];
if (_spot isEqualTo []) then {
    // nothing clear: the ideal point, or the nearest dry point short of it
    {
        private _q = _lPos getPos [AIC_RALLY_SPOT_DIST * _x, _dir];
        if (!surfaceIsWater _q) exitWith {_spot = [_q select 0, _q select 1, 0]};
    } forEach [1, 0.7, 0.4];
    if (_spot isEqualTo []) then {_spot = _lPos};
};

[_spot, [_cmd, _spot] call AIC_fnc_nearestBase, ""]
