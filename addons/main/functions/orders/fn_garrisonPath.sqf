/*
    Function: AIC_fnc_garrisonPath

    Description:
        Pathfinding of a garrison's men who hold their spot. Pathfinding is
        one of the most expensive parts of a unit's AI, and a man in his
        window has nowhere to walk: AIC_fnc_monitorGarrison switches it off
        for each man on foot who reached his spot (setting
        "garrisonHoldPath", the leader keeps it), the man still turns, aims
        and shoots. Unit variable "AIC_pathOff" marks what AIC switched off,
        group variable "AIC_pathHeld" that some man of the group is held.

        On (this function with true) for every held man of the group:
          - when the group is engaged (AIC_fnc_groupEngaged: a sighting, a
            hit, fire nearby, a man killed), so the garrison can move,
          - on every new order and when the group leaves command
            (AIC_fnc_clearWaypoints, AIC_fnc_registerGroups),
          - before the group is handed to a headless client
            (AIC_fnc_hcBalance: disabled AI features may not survive the
            change of owner).
        Off again (AIC_fnc_monitorGarrison) once the group has been calm for
        AIC_PATH_CALM s, for the men still at their spot (unit variable
        "AIC_garrisonSpot").

    Parameters:
        0: GROUP  - the group
        1: BOOL   - true: pathfinding back on for the held men; false: off
                    for the given men
        2: ARRAY  - (with false) the men to hold

    Returns:
        NUMBER - men switched

    Example:
        [_group, true] call AIC_fnc_garrisonPath;
        [_group, false, [_unit]] call AIC_fnc_garrisonPath;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_group", grpNull, [grpNull]], ["_on", true, [true]], ["_units", [], [[]]]];

if (isNull _group) exitWith { 0 };

if (_on) exitWith {
    if !(_group getVariable ["AIC_pathHeld", false]) exitWith { 0 };
    _group setVariable ["AIC_pathHeld", nil];
    private _held = (units _group) select { _x getVariable ["AIC_pathOff", false] };
    { _x setVariable ["AIC_pathOff", nil]; } forEach _held;
    // (one by one: enableAI / disableAI take a single unit)
    { [_x, "enableAI", "PATH"] call AIC_fnc_do; } forEach _held;
    count _held
};

private _leader = leader _group;
private _hold = _units select {
    alive _x && { _x isNotEqualTo _leader } && { isNull objectParent _x } && { !isPlayer _x }
    && { !(_x getVariable ["AIC_pathOff", false]) }
};
if (_hold isEqualTo []) exitWith { 0 };
{ _x setVariable ["AIC_pathOff", true]; } forEach _hold;
_group setVariable ["AIC_pathHeld", true];
{ [_x, "disableAI", "PATH"] call AIC_fnc_do; } forEach _hold;
count _hold
