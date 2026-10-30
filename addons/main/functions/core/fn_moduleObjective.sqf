/*
    Function: AIC_fnc_moduleObjective

    Description:
        Eden module function of AIC_ModuleObjective (server only).
        Normalises the module attributes on the logic ("Name", "Radius",
        "Priority"), stores the logic in AIC_objectiveModules so that
        commanders created later pick it up (AIC_fnc_collectObjectives),
        and adds the objective to every existing commander.

    Parameters:
        0: OBJECT - module logic
        1: ARRAY  - synchronised units (unused)
        2: BOOL   - activated

    Returns:
        BOOL - true

    Example:
        Called by the module framework.
*/

params [["_logic", objNull, [objNull]], ["_units", [], [[]]], ["_activated", true, [true]]];

if (!isServer) exitWith { true };
if (isNull _logic || { !_activated }) exitWith { true };

if (isNil "AIC_commanders") then { AIC_commanders = createHashMap; };
if (isNil "AIC_objectiveModules") then { AIC_objectiveModules = []; };

// --- normalise attributes
private _name = _logic getVariable ["Name", ""];
if !(_name isEqualType "") then { _name = str _name; };
if (_name isEqualTo "") then {
    _name = format ["Objective %1", count AIC_objectiveModules + 1];
};

private _radius = _logic getVariable ["Radius", 300];
if (_radius isEqualType "") then { _radius = parseNumber _radius; };
if (!(_radius isEqualType 0) || { _radius <= 0 }) then { _radius = 300; };

private _priority = _logic getVariable ["Priority", 2];
if (_priority isEqualType "") then { _priority = parseNumber _priority; };
if (!(_priority isEqualType 0) || { _priority <= 0 }) then { _priority = 1; };

_logic setVariable ["Name", _name];
_logic setVariable ["Radius", _radius];
_logic setVariable ["Priority", _priority];

AIC_objectiveModules pushBackUnique _logic;

// --- add to all running commanders
private _pos = getPosATL _logic;
{
    if (count _y > 0) then {
        [_y, _pos, _name, _radius, _priority, "MODULE"] call AIC_fnc_addObjective;
    };
} forEach AIC_commanders;

["Objective module '%1' registered at %2 (r %3, priority %4)", [_name, _pos apply { round _x }, _radius, _priority]] call AIC_fnc_log;

true
