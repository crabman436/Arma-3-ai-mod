/*
    Function: AIC_fnc_moduleCommander

    Description:
        Eden module function of AIC_ModuleCommander (server only).
        Reads the module attributes (including the logistics checkboxes
        ManageDynSim, ManageGarrisons, UseTransport and ManageCleanup), builds a settings
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

if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _objectiveModules = AIC_ns get "objectiveModules";

private _sideIndex = round ([_logic, "Side", 1] call AIC_fnc_moduleAttr);
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
    ["aggression", (([_logic, "Aggression", 0.5] call AIC_fnc_moduleAttr) max 0) min 1],
    ["loopInterval", ([_logic, "LoopInterval", 30] call AIC_fnc_moduleAttr) max 5],
    ["useArtillery", [_logic, "UseArtillery", true] call AIC_fnc_moduleAttr],
    ["useAir", [_logic, "UseAir", true] call AIC_fnc_moduleAttr],
    ["autoObjectives", [_logic, "AutoObjectives", true] call AIC_fnc_moduleAttr],
    ["debugMarkers", [_logic, "DebugMarkers", false] call AIC_fnc_moduleAttr],
    ["reportToPlayers", [_logic, "ReportToPlayers", true] call AIC_fnc_moduleAttr],
    ["manageDynSim", [_logic, "ManageDynSim", true] call AIC_fnc_moduleAttr],
    ["manageGarrisons", [_logic, "ManageGarrisons", true] call AIC_fnc_moduleAttr],
    ["useTransport", [_logic, "UseTransport", true] call AIC_fnc_moduleAttr],
    ["manageCleanup", [_logic, "ManageCleanup", true] call AIC_fnc_moduleAttr]
];

// --- synced objective modules: make sure they are known before objectives are collected
private _objModules = (synchronizedObjects _logic) select { typeOf _x == "AIC_ModuleObjective" };
{
    if (_x getVariable ["Name", ""] isEqualTo "" || { !(_x in _objectiveModules) }) then {
        // not initialised yet (or attributes not normalised): run its module function now
        [_x, [], true] call AIC_fnc_moduleObjective;
    };
} forEach _objModules;

private _cmd = [_side, _settings] call AIC_fnc_createCommander;
if (count _cmd == 0) exitWith { true };

// collectObjectives already reads AIC_ns "objectiveModules"; addObjective dedupes by id,
// this guarantees synced objectives even if the commander already existed.
{
    private _garrison = ([_x, "Garrison", 0] call AIC_fnc_moduleAttr) max 0;
    private _isBase = [_x, "IsBase", false] call AIC_fnc_moduleAttr;
    private _rec = [
        _cmd,
        getPosATL _x,
        [_x, "Name", "Objective"] call AIC_fnc_moduleAttr,
        [_x, "Radius", [_cmd, "objectiveRadius"] call AIC_fnc_getSetting] call AIC_fnc_moduleAttr,
        [_x, "Priority", 2] call AIC_fnc_moduleAttr,
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
