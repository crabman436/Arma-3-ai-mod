/*
 * Name: AIC_fnc_availableGroups
 * Description:
 *   Returns the commander's groups that can be given a manoeuvre task:
 *     - group not null and has alive units
 *     - record task is not "RETREAT", "TRANSPORT", "TRANSPORTED" or "RTB"
 *       (retreating groups and groups owned by the transport system)
 *     - record strength is above setting "retreatThreshold"
 *     - type filter: if a non-empty types array is given, only groups whose
 *       record type is in it; otherwise every type except "STATIC" and "ARTY".
 *   Groups without a record are ignored.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: ARRAY   - (optional) allowed type strings, e.g. ["HELI","PLANE"]. Default: []
 *
 * Returns:
 *   ARRAY - groups, sorted by descending power
 *
 * Example:
 *   private _ground = [_commander] call AIC_fnc_availableGroups;
 *   private _air = [_commander, ["HELI", "PLANE"]] call AIC_fnc_availableGroups;
 */

params [
    ["_commander", createHashMap, [createHashMap]],
    ["_types", [], [[]]]
];

if (count _commander == 0) exitWith {[]};

private _groups = _commander getOrDefault ["groups", []];
private _groupData = _commander getOrDefault ["groupData", createHashMap];
if (_groups isEqualTo [] || {!(_groupData isEqualType createHashMap)}) exitWith {[]};

private _threshold = [_commander, "retreatThreshold"] call AIC_fnc_getSetting;
if (isNil "_threshold" || {!(_threshold isEqualType 0)}) then {_threshold = 0.3};

private _excludedTasks = ["RETREAT", "TRANSPORT", "TRANSPORTED", "RTB"];

private _upperTypes = _types apply {toUpper _x};
private _useFilter = _upperTypes isNotEqualTo [];

private _result = [];
{
    private _grp = _x;
    if (!isNull _grp && {({alive _x} count (units _grp)) > 0}) then {
        private _record = _groupData getOrDefault [hashValue _grp, createHashMap];
        if (count _record > 0) then {
            private _type = _record getOrDefault ["type", "INF"];
            private _task = _record getOrDefault ["task", "IDLE"];
            private _strength = _record getOrDefault ["strength", 1];

            private _typeOk = if (_useFilter) then {
                _type in _upperTypes
            } else {
                !(_type in ["STATIC", "ARTY"])
            };

            if (_typeOk && {!(_task in _excludedTasks)} && {_strength > _threshold}) then {
                _result pushBack [_record getOrDefault ["power", 0], _forEachIndex];
            };
        };
    };
} forEach _groups;

// Sort [power, index] pairs only (numbers), then map back to groups
_result sort false;

_result apply {_groups select (_x select 1)}
