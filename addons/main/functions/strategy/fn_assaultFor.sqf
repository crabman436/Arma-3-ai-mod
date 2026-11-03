/*
 * Name: AIC_fnc_assaultFor
 * Description:
 *   The assault on an objective, created when the first group is ordered
 *   there (server only, setting "stagedAssaults"). An assault record lives in
 *   the commander's "assaults" HashMap under the objective id:
 *     "id", "pos"   - objective id and position
 *     "key"         - id plus creation time: lanes handed out by an earlier
 *                     assault on the same objective are not reused
 *     "stage"       - assembly area short of the objective, [] if there is none
 *     "dir"         - bearing from the objective to the assembly area
 *     "state"       - "STAGE" (groups gather) or "GO" (the assault is on)
 *     "time"        - time it was created
 *     "firstArrive" - time the first group reached the assembly area, or -1
 *     "urban"       - the objective is built up
 *     "hasInf"      - infantry is part of the assault
 *     "slots"       - lanes handed out so far
 *     "nightHold"   - the assault waits at the assembly area for the night
 *                     (setting "nightAssaults", urban objectives only;
 *                     AIC_fnc_assaultCycle sets it)
 *   AIC_fnc_assaultCycle adds "goTime", "escalated", "roles", "goPower",
 *   "reserveCommitted", "reserveAdvice" (the reserve went in on Jev
 *   advice), "prepTime" (preparatory fire called during STAGE),
 *   "contactTime" (first group going in near the objective: the GO clocks
 *   start) and "stagingReason" (why STAGE still waits).
 *   The assembly area is objective radius / 2 + 600 m out, on the first
 *   group's side (the HQ's side if that group is already close), or up to 90
 *   degrees around if that spot is wet or has an enemy known within 300 m,
 *   moved to the best cover within 200 m of it (AIC_fnc_bestPlace).
 *   An assault that finds no such spot starts in state "GO". A group whose
 *   leader is already inside the objective radius gets no assault (empty
 *   HashMap, an existing one is not returned either): it fights where it is
 *   and is never sent out to stage (AIC_fnc_issueOrder checks the same).
 *   No new assault is created on an objective whose last assault failed or
 *   was called off (objective "failedUntil" later than now, or the
 *   commander's "adviceAbort" [time, id] younger than
 *   AIC_ADVICE_ABORT_COOLDOWN): the empty HashMap is returned, and a group
 *   that still gets there attacks directly (AIC_fnc_orderAttack).
 *   AIC_fnc_drainOrders and AIC_fnc_allocateForces already keep new attacks
 *   off such an objective; this closes the last way in.
 *   AIC_fnc_orderAssault gives the groups their orders, AIC_fnc_assaultCycle
 *   starts the assault and ends it.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - group ordered to attack
 *   2: ARRAY   - objective position
 *   3: STRING  - objective id
 *
 * Returns:
 *   HASHMAP - the assault, empty for an objective-less attack, for a group
 *             already inside the objective, during an objective's failure /
 *             abort cooldown, or with "stagedAssaults" off
 *
 * Example:
 *   private _assault = [_cmd, _group, _pos, _objective] call AIC_fnc_assaultFor;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_target", [], [[]]],
    ["_objective", "", [""]]
];

if (!isServer || {_objective isEqualTo ""} || {count _target < 2}) exitWith {createHashMap};
if !(([_cmd, "stagedAssaults"] call AIC_fnc_getSetting) isEqualTo true) exitWith {createHashMap};

private _obj = [_cmd, _objective] call AIC_fnc_getObjective;
private _radius = _obj getOrDefault ["radius", 300];
private _pos = [_target select 0, _target select 1, 0];
private _dist = (leader _group) distance2D _pos;
// already in there: nothing to stage for
if (_dist < _radius) exitWith {createHashMap};

private _assaults = _cmd getOrDefault ["assaults", createHashMap];
if (_objective in _assaults) exitWith {_assaults get _objective};
// the last assault on it failed or was called off: no new one for a while
private _failedUntil = _obj getOrDefault ["failedUntil", -1];
if (_failedUntil isEqualType 0 && {_failedUntil > time}) exitWith {createHashMap};
private _abort = _cmd getOrDefault ["adviceAbort", []];
if (_abort isEqualType [] && {count _abort >= 2} && {(_abort select 1) isEqualTo _objective}
    && {(_abort select 0) isEqualType 0} && {(time - (_abort select 0)) < AIC_ADVICE_ABORT_COOLDOWN}) exitWith {createHashMap};
_cmd set ["assaults", _assaults];

private _stageDist = (_radius * 0.5) + AIC_ASSAULT_STAGE;

private _urban = _obj getOrDefault ["urban", -1];
if !(_urban isEqualType true) then {
    _urban = (count (nearestTerrainObjects [_pos, ["HOUSE", "BUILDING", "CHURCH", "CHAPEL"], (_radius min 300) max 50, false, true])) >= 12;
    // terrain never changes: kept on the objective, as AIC_fnc_allocateForces does
    if (count _obj > 0) then {_obj set ["urban", _urban]};
};

// an assembly area in the dry and away from known enemies, on the side the
// first group comes from, or the HQ's side if that group is already close
private _stage = [];
private _hq = _cmd getOrDefault ["hq", []];
private _dir = if (_dist > (_stageDist + 200) || { !(_hq isEqualType []) } || { count _hq < 2 }) then {
    _pos getDir (leader _group)
} else {
    _pos getDir _hq
};
{
        private _p = _pos getPos [_stageDist, _dir + _x];
        if (!surfaceIsWater _p && {([_cmd, _p, 300] call AIC_fnc_nearestThreat) isEqualTo []}) exitWith {
            _stage = [_p select 0, _p select 1, 0];
            _dir = _dir + _x;
        };
} forEach [0, 45, -45, 90, -90];
// then the best cover near that spot: woods and folds in the ground, not houses
if (_stage isNotEqualTo []) then {
    private _better = [_stage, 200, "forest + trees + 0.5*hills - 2*houses - 10*sea"] call AIC_fnc_bestPlace;
    if (_better isNotEqualTo [] && {([_cmd, _better, 300] call AIC_fnc_nearestThreat) isEqualTo []}) then {
        _stage = _better;
        _dir = _pos getDir _stage;
    };
};

private _assault = createHashMapFromArray [
    ["id", _objective],
    ["key", format ["%1@%2", _objective, round time]],
    ["pos", _pos],
    ["stage", _stage],
    ["dir", _dir],
    ["state", ["GO", "STAGE"] select (_stage isNotEqualTo [])],
    ["time", time],
    ["firstArrive", -1],
    ["urban", _urban],
    ["hasInf", true],
    ["slots", 0],
    ["nightHold", false]
];
_assaults set [_objective, _assault];

["%1: assault on '%2' planned, %3", [
    _cmd getOrDefault ["side", sideUnknown], _objective,
    if (_stage isEqualTo []) then {"going straight in"} else {format ["assembly area %1", _stage apply {round _x}]}
]] call AIC_fnc_log;

_assault
