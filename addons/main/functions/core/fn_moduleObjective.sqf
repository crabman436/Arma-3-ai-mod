/*
    Function: AIC_fnc_moduleObjective

    Description:
        Eden module function of AIC_ModuleObjective (server only).
        Normalises the module attributes on the logic ("Name", "Radius",
        "Priority", "Garrison" (number >= 0, 0 = auto) and "IsBase"
        (bool)), stores the logic in AIC_ns "objectiveModules" so that
        commanders created later pick it up (AIC_fnc_collectObjectives),
        and adds the objective to every existing commander (setting the
        record keys "garrison" and "isBase" from the module).

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

if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _objectiveModules = AIC_ns get "objectiveModules";

// --- normalise attributes
private _name = _logic getVariable ["Name", ""];
if !(_name isEqualType "") then { _name = str _name; };
if (_name isEqualTo "") then {
    _name = format ["Objective %1", count _objectiveModules + 1];
};

private _radius = _logic getVariable ["Radius", 300];
if (_radius isEqualType "") then { _radius = parseNumber _radius; };
if (!(_radius isEqualType 0) || { _radius <= 0 }) then { _radius = 300; };

private _priority = _logic getVariable ["Priority", 2];
if (_priority isEqualType "") then { _priority = parseNumber _priority; };
if (!(_priority isEqualType 0) || { _priority <= 0 }) then { _priority = 1; };

private _garrison = _logic getVariable ["Garrison", 0];
if (_garrison isEqualType "") then { _garrison = parseNumber _garrison; };
if !(_garrison isEqualType 0) then { _garrison = 0; };
_garrison = _garrison max 0;

private _isBase = _logic getVariable ["IsBase", false];
if (_isBase isEqualType 0) then { _isBase = _isBase > 0; };
if (_isBase isEqualType "") then { _isBase = (toLowerANSI _isBase) in ["true", "1"]; };
if !(_isBase isEqualType true) then { _isBase = false; };

_logic setVariable ["Name", _name];
_logic setVariable ["Radius", _radius];
_logic setVariable ["Priority", _priority];
_logic setVariable ["Garrison", _garrison];
_logic setVariable ["IsBase", _isBase];

_objectiveModules pushBackUnique _logic;

// --- add to all running commanders
private _pos = getPosATL _logic;
{
    if (count _y > 0) then {
        private _rec = [_y, _pos, _name, _radius, _priority, "MODULE", _isBase, _garrison] call AIC_fnc_addObjective;
        if (count _rec > 0) then {
            _rec set ["garrison", _garrison];
            _rec set ["isBase", _isBase];
        };
    };
} forEach (AIC_ns get "commanders");

["Objective module '%1' registered at %2 (r %3, priority %4, garrison %5, base %6)", [_name, _pos apply { round _x }, _radius, _priority, _garrison, _isBase]] call AIC_fnc_log;

true
