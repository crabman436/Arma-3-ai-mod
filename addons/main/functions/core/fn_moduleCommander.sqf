/*
    Function: AIC_fnc_moduleCommander

    Description:
        Eden module function of AIC_ModuleCommander (server only).
        Reads the module attributes (including the logistics checkboxes
        ManageDynSim, ManageGarrisons and UseTransport), builds a settings
        HashMap and creates the commander via AIC_fnc_createCommander. Objective modules
        synchronised to this module are registered and added to the
        commander. When the module is deactivated (synced trigger
        deactivates) the commander of that side is removed.

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
if (isNull _logic) exitWith { true };

if (isNil "AIC_commanders") then { AIC_commanders = createHashMap; };
if (isNil "AIC_objectiveModules") then { AIC_objectiveModules = []; };

// --- attribute helpers
private _fnc_num = {
    params ["_value", "_default"];
    if (isNil "_value") exitWith { _default };
    if (_value isEqualType 0) exitWith { _value };
    if (_value isEqualType "") exitWith { parseNumber _value };
    if (_value isEqualType true) exitWith { [0, 1] select _value };
    _default
};
private _fnc_bool = {
    params ["_value", "_default"];
    if (isNil "_value") exitWith { _default };
    if (_value isEqualType true) exitWith { _value };
    if (_value isEqualType 0) exitWith { _value > 0 };
    if (_value isEqualType "") exitWith { (toLower _value) in ["true", "1"] };
    _default
};

private _sideIndex = round ([_logic getVariable ["Side", 1], 1] call _fnc_num);
private _side = [west, east, independent] select ((_sideIndex max 0) min 2);

// --- deactivation removes the commander
if (!_activated) exitWith {
    if (count ([_side] call AIC_fnc_getCommander) > 0) then {
        [_side] call AIC_fnc_removeCommander;
    };
    true
};

// --- settings
private _settings = createHashMapFromArray [
    ["aggression", (([_logic getVariable ["Aggression", 0.5], 0.5] call _fnc_num) max 0) min 1],
    ["loopInterval", ([_logic getVariable ["LoopInterval", 30], 30] call _fnc_num) max 5],
    ["useArtillery", [_logic getVariable ["UseArtillery", true], true] call _fnc_bool],
    ["useAir", [_logic getVariable ["UseAir", true], true] call _fnc_bool],
    ["autoObjectives", [_logic getVariable ["AutoObjectives", true], true] call _fnc_bool],
    ["debugMarkers", [_logic getVariable ["DebugMarkers", false], false] call _fnc_bool],
    ["reportToPlayers", [_logic getVariable ["ReportToPlayers", true], true] call _fnc_bool],
    ["manageDynSim", [_logic getVariable ["ManageDynSim", true], true] call _fnc_bool],
    ["manageGarrisons", [_logic getVariable ["ManageGarrisons", true], true] call _fnc_bool],
    ["useTransport", [_logic getVariable ["UseTransport", true], true] call _fnc_bool]
];

// --- synced objective modules: make sure they are known before objectives are collected
private _objModules = (synchronizedObjects _logic) select { typeOf _x == "AIC_ModuleObjective" };
{
    if (_x getVariable ["Name", ""] isEqualTo "" || { !(_x in AIC_objectiveModules) }) then {
        // not initialised yet (or attributes not normalised): run its module function now
        [_x, [], true] call AIC_fnc_moduleObjective;
    };
} forEach _objModules;

private _cmd = [_side, _settings] call AIC_fnc_createCommander;
if (count _cmd == 0) exitWith { true };

// collectObjectives already reads AIC_objectiveModules; addObjective dedupes by id,
// this guarantees synced objectives even if the commander already existed.
{
    private _garrison = ([_x getVariable ["Garrison", 0], 0] call _fnc_num) max 0;
    private _isBase = [_x getVariable ["IsBase", false], false] call _fnc_bool;
    private _rec = [
        _cmd,
        getPosATL _x,
        _x getVariable ["Name", "Objective"],
        _x getVariable ["Radius", [_cmd, "objectiveRadius"] call AIC_fnc_getSetting],
        _x getVariable ["Priority", 1],
        "MODULE",
        _isBase,
        _garrison
    ] call AIC_fnc_addObjective;
    if (count _rec > 0) then {
        _rec set ["garrison", _garrison];
        _rec set ["isBase", _isBase];
    };
} forEach _objModules;

_logic setVariable ["AIC_side", _side];

true
