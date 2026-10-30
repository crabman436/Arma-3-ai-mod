/*
    Function: AIC_fnc_createCommander

    Description:
        Creates the AI general for a side (server only). Merges the given
        settings with the defaults, stores the commander in AIC_commanders,
        registers the side's groups, sets the HQ (average position of its
        groups), collects objectives and starts the commander loop.
        If the side already has a commander, that commander is returned
        unchanged.

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

params [["_side", sideUnknown, [sideUnknown]], ["_userSettings", createHashMap, [createHashMap]]];

if (!isServer) exitWith { createHashMap };

if (isNil "AIC_commanders") then { AIC_commanders = createHashMap; };
if (isNil "AIC_objectiveModules") then { AIC_objectiveModules = []; };
if (isNil "AIC_debug") then { AIC_debug = false; };

if !(_side in [west, east, independent, civilian]) exitWith {
    ["createCommander: invalid side %1", [_side]] call AIC_fnc_log;
    createHashMap
};

private _existing = AIC_commanders getOrDefault [_side, createHashMap];
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

// --- commander state
private _cmd = createHashMapFromArray [
    ["side", _side],
    ["enabled", true],
    ["settings", _settings],
    ["hq", [worldSize / 2, worldSize / 2, 0]],
    ["groups", []],
    ["groupData", createHashMap],
    ["objectives", []],
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
    ["loopHandle", scriptNull]
];

AIC_commanders set [_side, _cmd];

// --- groups under command
[_cmd] call AIC_fnc_registerGroups;

// --- HQ: average leader position of commanded groups
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
_cmd set ["hq", _hq];

// --- objectives (needs HQ for nearest auto objectives)
[_cmd] call AIC_fnc_collectObjectives;

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
