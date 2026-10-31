/*
    Function: AIC_fnc_flightPath

    Description:
        Finds a detour for a transport helicopter around what the commander
        knows to be hostile: threat clusters, known contacts and objectives
        held by an enemy side. The hostile spot closest to the start that lies
        within AIC_AIR_AVOID_RADIUS of the straight line is passed on the side
        that stays farther from every other hostile spot. Spots close to the
        start or the end are ignored: the pickup and the LZ are chosen
        separately. Only what is known can be avoided, and only one spot is
        flown around.

    Parameters:
        0: HASHMAP - commander
        1: ARRAY   - start position
        2: ARRAY   - end position

    Returns:
        ARRAY - detour position [x, y, 0], or [] if the straight line is clear

    Example:
        private _via = [_cmd, _pickupPos, _dropPos] call AIC_fnc_flightPath;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_from", [], [[]]],
    ["_to", [], [[]]]
];

if (count _cmd == 0 || { count _from < 2 } || { count _to < 2 }) exitWith { [] };

private _length = _from distance2D _to;
if (_length < 2 * AIC_AIR_AVOID_RADIUS) exitWith { [] };

private _side = _cmd getOrDefault ["side", sideUnknown];
private _spots = [];
{
    if (_x isEqualType createHashMap) then {
        private _p = _x getOrDefault ["pos", []];
        if (_p isEqualType [] && { count _p >= 2 }) then { _spots pushBack _p; };
    };
} forEach ((_cmd getOrDefault ["threats", []]) + (_cmd getOrDefault ["knownEnemies", []]));
{
    if (_x isEqualType createHashMap) then {
        private _owner = _x getOrDefault ["owner", sideUnknown];
        private _p = _x getOrDefault ["pos", []];
        if (
            _owner in [west, east, independent, civilian]
            && { _owner isNotEqualTo _side }
            && { (_side getFriend _owner) < AIC_HOSTILE_FRIEND }
            && { _p isEqualType [] && { count _p >= 2 } }
        ) then { _spots pushBack _p; };
    };
} forEach (_cmd getOrDefault ["objectives", []]);
if (_spots isEqualTo []) exitWith { [] };

// the first hostile spot along the line
private _dir = _from getDir _to;
private _ax = sin _dir;
private _ay = cos _dir;
private _best = [];
private _bestAlong = 1e9;
{
    private _dx = (_x select 0) - (_from select 0);
    private _dy = (_x select 1) - (_from select 1);
    private _along = _dx * _ax + _dy * _ay;
    private _across = abs (_dx * _ay - _dy * _ax);
    if (
        _across < AIC_AIR_AVOID_RADIUS
        && { _along > AIC_AIR_AVOID_RADIUS }
        && { _along < (_length - AIC_AIR_AVOID_RADIUS) }
        && { _along < _bestAlong }
    ) then {
        _bestAlong = _along;
        _best = _x;
    };
} forEach _spots;
if (_best isEqualTo []) exitWith { [] };

// fly past it on the side with more room
private _fnc_room = {
    params ["_p"];
    private _room = 1e9;
    { _room = _room min (_p distance2D _x); } forEach _spots;
    _room
};
private _left = _best getPos [2 * AIC_AIR_AVOID_RADIUS, _dir - 90];
private _right = _best getPos [2 * AIC_AIR_AVOID_RADIUS, _dir + 90];
private _via = if (([_left] call _fnc_room) > ([_right] call _fnc_room)) then { _left } else { _right };

[_via select 0, _via select 1, 0]
