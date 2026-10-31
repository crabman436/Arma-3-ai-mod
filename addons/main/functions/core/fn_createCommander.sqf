/*
    Function: AIC_fnc_createCommander

    Description:
        Creates the AI general for a side (server only). Merges the given
        settings with the defaults, stores the commander in AIC_ns "commanders",
        registers the side's groups, sets the HQ, collects objectives, adds the implicit base objective
        "BASE_HQ" at the HQ (isBase = true, owner = own side) and starts
        the commander loop. If "manageDynSim" is on, the engine's dynamic
        simulation system is enabled (and the group activation distance is
        set from "dynSimDistance" when > 0).
        If the side already has a commander, that commander is returned
        unchanged.
        HQ: the base marker of the side (aic_base_<side>*, case-insensitive)
        nearest to the average leader position of its groups; without such
        a marker the average itself, moved to the nearest leader on land if
        it falls into water. Without groups: the side's respawn marker,
        else the map centre (a base marker still wins).

    Parameters:
        0: SIDE    - side to command (west, east, independent, civilian)
        1: HASHMAP - (optional) settings overriding the defaults

    Returns:
        HashMap - the commander (empty HashMap on failure / non-server)

    Example:
        [east] call AIC_fnc_createCommander;
        private _s = createHashMapFromArray [["aggression", 0.8], ["debugMarkers", true]];
        [west, _s] call AIC_fnc_createCommander;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_side", sideUnknown, [sideUnknown]], ["_userSettings", createHashMap, [createHashMap]]];

if (!isServer) exitWith { createHashMap };

if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _commanders = AIC_ns get "commanders";

if !(_side in [west, east, independent, civilian]) exitWith {
    ["createCommander: invalid side %1", [_side]] call AIC_fnc_log;
    createHashMap
};

private _existing = _commanders getOrDefault [_side, createHashMap];
if (count _existing > 0) exitWith {
    ["createCommander: commander for %1 already exists", [_side]] call AIC_fnc_log;
    _existing
};

// --- settings: defaults + user overrides (type-checked against defaults)
private _settings = [] call AIC_fnc_defaultSettings;
{
    private _key = _x;
    private _value = _y;
    if (isNil "_value") then { continue };
    if (_key in _settings) then {
        private _default = _settings get _key;
        if (_value isEqualType _default) then {
            _settings set [_key, _value];
        } else {
            ["createCommander: setting '%1' has wrong type (%2), keeping default %3", [_key, typeName _value, _default]] call AIC_fnc_log;
        };
    } else {
        // unknown keys are kept so other subsystems / mission makers can extend settings
        _settings set [_key, _value];
    };
} forEach _userSettings;

// sanitise numeric ranges
_settings set ["aggression", ((_settings get "aggression") max 0) min 1];
_settings set ["retreatThreshold", ((_settings get "retreatThreshold") max 0) min 1];
_settings set ["reserveRatio", ((_settings get "reserveRatio") max 0) min 1];
_settings set ["loopInterval", (_settings get "loopInterval") max 5];
_settings set ["objectiveRadius", (_settings get "objectiveRadius") max 25];
_settings set ["maxAutoObjectives", (round (_settings get "maxAutoObjectives")) max 0];
_settings set ["artyCooldown", (_settings get "artyCooldown") max 0];
_settings set ["airCooldown", (_settings get "airCooldown") max 0];
_settings set ["dynSimWakeRange", (_settings get "dynSimWakeRange") max 50];
_settings set ["dynSimDistance", (_settings get "dynSimDistance") max 0];
_settings set ["garrisonPerPriority", (_settings get "garrisonPerPriority") max 0];
_settings set ["garrisonMovesPerCycle", (round (_settings get "garrisonMovesPerCycle")) max 0];
_settings set ["transportMinDistance", (_settings get "transportMinDistance") max 0];
_settings set ["heliTransportDistance", (_settings get "heliTransportDistance") max 0];
_settings set ["transportSearchRadius", (_settings get "transportSearchRadius") max 0];
_settings set ["cleanupDelay", (_settings get "cleanupDelay") max 0];
_settings set ["cleanupPlayerDistance", (_settings get "cleanupPlayerDistance") max 0];
_settings set ["cleanupMaxPerCycle", (round (_settings get "cleanupMaxPerCycle")) max 0];

// --- commander state
private _cmd = createHashMapFromArray [
    ["side", _side],
    ["enabled", true],
    ["settings", _settings],
    ["hq", [worldSize / 2, worldSize / 2, 0]],
    ["groups", []],
    ["groupData", createHashMap],
    ["objectives", []],
    ["objectiveIndex", createHashMap],
    ["knownEnemies", []],
    ["threats", []],
    ["stance", "BALANCED"],
    ["plan", []],
    ["ownPower", 0],
    ["enemyPower", 0],
    ["lastPlanTime", -1e6],
    ["lastArtyTime", -1e6],
    ["lastAirTime", -1e6],
    ["markers", []],
    ["garrisons", createHashMap],
    ["deadQueue", []],
    ["loopHandle", scriptNull]
];

_commanders set [_side, _cmd];

// --- groups under command
[_cmd] call AIC_fnc_registerGroups;

// --- HQ: average leader position of commanded groups (refined below)
private _groups = (_cmd getOrDefault ["groups", []]) select { !isNull _x && { !isNull leader _x } };
private _hq = [];
if (count _groups > 0) then {
    private _sum = [0, 0, 0];
    { _sum = _sum vectorAdd (getPosATL leader _x); } forEach _groups;
    _hq = _sum vectorMultiply (1 / count _groups);
    _hq set [2, 0];
} else {
    // fallback: side respawn marker, otherwise map centre
    private _marker = switch (_side) do {
        case west: { "respawn_west" };
        case east: { "respawn_east" };
        case independent: { "respawn_guerrila" };
        default { "respawn_civilian" };
    };
    if (markerType _marker != "") then {
        _hq = getMarkerPos _marker;
        _hq set [2, 0];
    } else {
        _hq = [worldSize / 2, worldSize / 2, 0];
    };
};

// The average of a split army can land in a field between its bases or in
// the sea. A base marker placed by the mission maker is the better HQ.
private _basePrefix = AIC_MARKER_BASE_PREFIX + toLowerANSI str _side;
private _baseMarkers = allMapMarkers select { ((toLowerANSI _x) find _basePrefix) == 0 };
if (_baseMarkers isNotEqualTo []) then {
    private _avg = +_hq;
    private _bestD = 1e12;
    {
        private _mPos = getMarkerPos _x;
        private _d = _mPos distance2D _avg;
        if (_d < _bestD) then { _bestD = _d; _hq = [_mPos select 0, _mPos select 1, 0]; };
    } forEach _baseMarkers;
} else {
    if (surfaceIsWater _hq) then {
        private _landLeaders = (_groups apply { leader _x }) select { !surfaceIsWater (getPosATL _x) };
        if (_landLeaders isNotEqualTo []) then {
            private _avg = +_hq;
            private _bestD = 1e12;
            {
                private _lPos = getPosATL _x;
                private _d = _lPos distance2D _avg;
                if (_d < _bestD) then { _bestD = _d; _hq = [_lPos select 0, _lPos select 1, 0]; };
            } forEach _landLeaders;
        };
    };
};
_cmd set ["hq", _hq];

// --- objectives (needs HQ for nearest auto objectives)
[_cmd] call AIC_fnc_collectObjectives;

// --- implicit base objective at the HQ (garrison system home of last
// resort). AIC_fnc_collectObjectives has already added BASE_HQ at this very
// "hq", so addObjective returns that record (it dedupes by id and place).
private _baseRadius = ([_cmd, "objectiveRadius"] call AIC_fnc_getSetting) min 300;
private _base = [_cmd, _hq, "HQ", _baseRadius, 1, "BASE", true, 0] call AIC_fnc_addObjective;
if (count _base == 0) then {
    ["createCommander: could not add the HQ base objective for %1 at %2", [_side, _hq apply { round _x }]] call AIC_fnc_log;
} else {
    _base set ["isBase", true];
    _base set ["owner", _side];
    if !((_base getOrDefault ["garrison", 0]) isEqualType 0) then { _base set ["garrison", 0]; };
};

// --- dynamic simulation: engine system on so parked groups freeze while no player is near
if (([_cmd, "manageDynSim"] call AIC_fnc_getSetting) isEqualTo true) then {
    enableDynamicSimulationSystem true;
    private _dsDist = [_cmd, "dynSimDistance"] call AIC_fnc_getSetting;
    if (_dsDist > 0) then {
        "Group" setDynamicSimulationDistance _dsDist;
    };
    ["createCommander: dynamic simulation managed for %1 (group distance %2)", [_side, dynamicSimulationDistance "Group"]] call AIC_fnc_log;
};

// --- start thinking
private _handle = [_cmd] spawn AIC_fnc_commanderLoop;
_cmd set ["loopHandle", _handle];

["Commander created for %1: %2 groups, %3 objectives, HQ %4", [
    _side,
    count (_cmd getOrDefault ["groups", []]),
    count (_cmd getOrDefault ["objectives", []]),
    _hq apply { round _x }
]] call AIC_fnc_log;

_cmd
