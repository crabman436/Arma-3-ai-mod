/*
 * Name: AIC_fnc_assaultFor
 * Description:
 *   The assault on an objective, created when the first group is ordered
 *   there (server only, setting "stagedAssaults"). An assault record lives in
 *   the commander's "assaults" HashMap under the objective id:
 *     "id", "pos"   - objective id and position
 *     "stage"       - assembly area short of the objective, [] if there is none
 *     "dir"         - bearing from the objective to the assembly area
 *     "state"       - "STAGE" (groups gather) or "GO" (the assault is on)
 *     "time"        - time it was created
 *     "firstArrive" - time the first group reached the assembly area, or -1
 *     "urban"       - the objective is built up
 *     "hasInf"      - infantry is part of the assault
 *     "slots"       - lanes handed out so far
 *   The assembly area is objective radius / 2 + 600 m out, on the first
 *   group's side, or up to 90 degrees around if that spot is wet or has an
 *   enemy known within 300 m. An assault that finds no such spot, or whose
 *   first group is already close, starts in state "GO".
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
 *   HASHMAP - the assault, empty for an objective-less attack or with
 *             "stagedAssaults" off
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

private _assaults = _cmd getOrDefault ["assaults", createHashMap];
if (_objective in _assaults) exitWith {_assaults get _objective};
_cmd set ["assaults", _assaults];

private _obj = [_cmd, _objective] call AIC_fnc_getObjective;
private _radius = _obj getOrDefault ["radius", 300];
private _pos = [_target select 0, _target select 1, 0];
private _dist = (leader _group) distance2D _pos;
private _stageDist = (_radius * 0.5) + AIC_ASSAULT_STAGE;

private _urban = _obj getOrDefault ["urban", -1];
if !(_urban isEqualType true) then {
    _urban = (count (nearestTerrainObjects [_pos, ["HOUSE", "BUILDING", "CHURCH", "CHAPEL"], (_radius min 300) max 50, false, true])) >= 12;
};

// an assembly area in the dry and away from known enemies
private _stage = [];
private _dir = _pos getDir (leader _group);
if (_dist > (_stageDist + 200)) then {
    {
        private _p = _pos getPos [_stageDist, _dir + _x];
        if (!surfaceIsWater _p && {([_cmd, _p, 300] call AIC_fnc_nearestThreat) isEqualTo []}) exitWith {
            _stage = [_p select 0, _p select 1, 0];
            _dir = _dir + _x;
        };
    } forEach [0, 45, -45, 90, -90];
};

private _assault = createHashMapFromArray [
    ["id", _objective],
    ["pos", _pos],
    ["stage", _stage],
    ["dir", _dir],
    ["state", ["GO", "STAGE"] select (_stage isNotEqualTo [])],
    ["time", time],
    ["firstArrive", -1],
    ["urban", _urban],
    ["hasInf", true],
    ["slots", 0]
];
_assaults set [_objective, _assault];

["%1: assault on '%2' planned, %3", [
    _cmd getOrDefault ["side", sideUnknown], _objective,
    if (_stage isEqualTo []) then {"going straight in"} else {format ["assembly area %1", _stage apply {round _x}]}
]] call AIC_fnc_log;

_assault
