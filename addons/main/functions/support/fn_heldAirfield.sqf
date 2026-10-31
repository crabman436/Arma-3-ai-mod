/*
    Function: AIC_fnc_heldAirfield

    Description:
        The nearest airfield the commander holds: one within an owned
        objective's radius plus AIC_AIRFIELD_HOLD_RANGE (bases and towns
        alike, "BASE_HQ" included). Planes land there to rearm
        (AIC_fnc_rearmCycle).

    Parameters:
        0: HASHMAP - commander
        1: ARRAY   - position to measure from

    Returns:
        ARRAY - [id, [x, y, 0]] of the airfield, [] if the side holds none

    Example:
        private _field = [_cmd, getPosATL _plane] call AIC_fnc_heldAirfield;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_pos", [], [[]]]
];

if (count _cmd == 0 || { count _pos < 2 }) exitWith { [] };
private _side = _cmd getOrDefault ["side", sideUnknown];
private _owned = (_cmd getOrDefault ["objectives", []]) select {
    _x isEqualType createHashMap
    && { count (_x getOrDefault ["pos", []]) >= 2 }
    && { (_x getOrDefault ["id", ""]) isEqualTo AIC_BASE_ID || { (_x getOrDefault ["owner", sideUnknown]) isEqualTo _side } }
};
if (_owned isEqualTo []) exitWith { [] };

private _best = [];
private _bestDist = 1e9;
{
    _x params ["", "_fPos"];
    private _held = (_owned findIf {
        (_fPos distance2D (_x get "pos")) <= ((_x getOrDefault ["radius", 300]) + AIC_AIRFIELD_HOLD_RANGE)
    }) >= 0;
    if (_held && { (_fPos distance2D _pos) < _bestDist }) then {
        _bestDist = _fPos distance2D _pos;
        _best = _x;
    };
} forEach (call AIC_fnc_airfields);

_best
