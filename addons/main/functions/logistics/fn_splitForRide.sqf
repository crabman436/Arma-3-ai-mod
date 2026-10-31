/*
 * Name: AIC_fnc_splitForRide
 * Description:
 *   Called by AIC_fnc_issueOrder when no single vehicle fits an infantry
 *   group. Tries 2, then up to AIC_TEAM_MAX teams, and splits only if every
 *   team finds its own vehicle: a squad either rides as a whole or walks as a
 *   whole, it is never left half on foot. The new teams are ordered here, so
 *   each gets its ride through the normal AIC_fnc_issueOrder path. The caller
 *   then looks for a ride for the original group, now small enough.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - group too big for one vehicle
 *   2: ARRAY   - destination
 *   3: STRING  - task of the order
 *   4: STRING  - objective id of the order
 *
 * Returns:
 *   BOOL - true if the group was split
 *
 * Example:
 *   if ([_cmd, _group, _pos, _task, _objective] call AIC_fnc_splitForRide) then { ... };
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_pos", [], [[]]],
    ["_task", "", [""]],
    ["_objective", "", [""]]
];

if (!isServer) exitWith {false};
if !(([_cmd, "dynamicSquads"] call AIC_fnc_getSetting) isEqualTo true) exitWith {false};
private _rec = (_cmd getOrDefault ["groupData", createHashMap]) getOrDefault [hashValue _group, createHashMap];
if ((_rec getOrDefault ["teamId", 0]) > 0) exitWith {false};

private _total = {alive _x} count (units _group);
private _teams = 0;
for "_n" from 2 to AIC_TEAM_MAX do {
    private _size = ceil (_total / _n);
    if (floor (_total / _n) < AIC_TEAM_MIN_SIZE) exitWith {};
    private _taken = [];
    for "_t" from 1 to _n do {
        private _tGrp = [_cmd, _group, _pos, _size, _taken] call AIC_fnc_findTransport;
        if (isNull _tGrp) exitWith {};
        _taken pushBack _tGrp;
    };
    if ((count _taken) == _n) exitWith {_teams = _n};
};
if (_teams == 0) exitWith {false};

private _new = [_cmd, _group, _teams] call AIC_fnc_splitGroup;
if (_new isEqualTo []) exitWith {false};

private _groupData = _cmd get "groupData";
{
    // a garrison transfer: the team already belongs to the town it rides to
    if (_task isEqualTo "DEFEND" && {_objective isNotEqualTo ""}) then {
        (_groupData get (hashValue _x)) set ["home", _objective];
    };
    [_cmd, _x, _task, _pos, _objective] call AIC_fnc_issueOrder;
} forEach _new;

true
