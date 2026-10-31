/*
    Function: AIC_fnc_collectObjectives

    Description:
        Builds (or extends) a commander's objective list from these sources,
        in this order:
          1. Eden objective modules stored in AIC_ns "objectiveModules"
             (logic variables "Name", "Radius", "Priority", and the
             logistics attributes "Garrison" (number, default 0 = auto) and
             "IsBase" (checkbox, default false)).
          2. Map markers whose name starts with "aic_obj" (case-insensitive).
             Name = marker text (or marker name if no text). Area markers
             (ELLIPSE / RECTANGLE) use their largest half-size as radius,
             other markers use the "objectiveRadius" setting. Priority 1.5,
             or the number after "_p" in the marker name if present
             (e.g. "aic_obj_bridge_p3" -> priority 3).
          2b. Base markers of this commander's side only: names starting with
             "aic_base_<side>" (case-insensitive, <side> = west, east, guer
             or civ). They become base objectives (source "BASE",
             isBase true, owned by the commander's side), priority 1 or the
             "_p<number>" suffix, radius as for "aic_obj" markers.
          3. If setting "autoObjectives": map locations of type
             NameCityCapital (priority 3), NameCity (2), Airport (2.5) and
             NameVillage (1), nearest to the commander HQ, until the commander
             holds "maxAutoObjectives" LOCATION objectives. A location is
             skipped if an existing non-"BASE" objective already covers its
             centre (a base inside a town does not hide the town).
          4. The implicit base objective "BASE_HQ" at the commander's "hq"
             (isBase, priority 1, radius min(objectiveRadius, 300), owner =
             own side), if it does not exist yet.
        Safe to call repeatedly: AIC_fnc_addObjective dedupes by id.

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - number of objectives the commander now has

    Example:
        [_cmd] call AIC_fnc_collectObjectives;
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith { 0 };

if !((_cmd getOrDefault ["objectives", []]) isEqualType []) then { _cmd set ["objectives", []]; };
if !("objectives" in _cmd) then { _cmd set ["objectives", []]; };

private _defRadius = [_cmd, "objectiveRadius"] call AIC_fnc_getSetting;
if (_defRadius <= 0) then { _defRadius = [createHashMap, "objectiveRadius"] call AIC_fnc_getSetting; };

// ---------------------------------------------------------------- 1. modules
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _objectiveModules = AIC_ns getOrDefault ["objectiveModules", []];
if (_objectiveModules isEqualType []) then {
    {
        private _logic = _x;
        if (!isNull _logic) then {
            // AIC_fnc_moduleAttr: the same normalisation AIC_fnc_moduleObjective uses
            // (addObjective maps radius <= 0 to the default and priority <= 0 to 1)
            private _name = [_logic, "Name", ""] call AIC_fnc_moduleAttr;
            private _radius = [_logic, "Radius", _defRadius] call AIC_fnc_moduleAttr;
            private _priority = [_logic, "Priority", 2] call AIC_fnc_moduleAttr;
            private _garrison = ([_logic, "Garrison", 0] call AIC_fnc_moduleAttr) max 0;
            private _isBase = [_logic, "IsBase", false] call AIC_fnc_moduleAttr;
            [_cmd, getPosATL _logic, _name, _radius, _priority, "MODULE", _isBase, _garrison] call AIC_fnc_addObjective;
        };
    } forEach _objectiveModules;
};

// last "_p<number>" in a lower-case marker name -> priority, else the default
private _fnc_markerPriority = {
    params ["_lower", "_default"];
    private _priority = _default;
    private _pIdx = -1;
    private _from = 0;
    while { true } do {
        private _i = (_lower select [_from]) find "_p";
        if (_i < 0) exitWith {};
        _pIdx = _from + _i;
        _from = _pIdx + 2;
    };
    if (_pIdx > 0) then {
        private _num = parseNumber (_lower select [_pIdx + 2]);
        if (_num > 0) then { _priority = _num; };
    };
    _priority
};

// area markers: largest half-size, else the default radius
private _fnc_markerRadius = {
    params ["_marker"];
    private _radius = _defRadius;
    if ((markerShape _marker) in ["ELLIPSE", "RECTANGLE"]) then {
        private _size = markerSize _marker;
        _radius = ((_size select 0) max (_size select 1)) max 25;
    };
    _radius
};

// ---------------------------------------------------------------- 2. markers
{
    private _marker = _x;
    private _lower = toLowerANSI _marker;
    if ((_lower find AIC_MARKER_OBJ_PREFIX) == 0) then {
        private _name = markerText _marker;
        if (_name isEqualTo "") then { _name = _marker; };

        private _radius = [_marker] call _fnc_markerRadius;
        private _priority = [_lower, 1.5] call _fnc_markerPriority;

        [_cmd, getMarkerPos _marker, _name, _radius, _priority, "MARKER"] call AIC_fnc_addObjective;
    };
} forEach allMapMarkers;

// ---------------------------------------------------------------- 2b. base markers (own side only)
private _side = _cmd getOrDefault ["side", sideUnknown];
private _basePrefix = AIC_MARKER_BASE_PREFIX + toLowerANSI str _side; // west / east / guer / civ
if (_side in [west, east, independent, civilian]) then {
    {
        private _marker = _x;
        private _lower = toLowerANSI _marker;
        if ((_lower find _basePrefix) == 0) then {
            private _name = markerText _marker;
            // id "BASE_<name>": a marker labelled "HQ" must not take the id
            // of the implicit base at the commander's "hq"
            if (_name isEqualTo "" || { format ["BASE_%1", _name] == AIC_BASE_ID }) then { _name = _marker; };
            private _radius = [_marker] call _fnc_markerRadius;
            private _priority = [_lower, 1] call _fnc_markerPriority;
            [_cmd, getMarkerPos _marker, _name, _radius, _priority, "BASE", true, 0] call AIC_fnc_addObjective;
        };
    } forEach allMapMarkers;
};

// ---------------------------------------------------------------- 3. locations
if (([_cmd, "autoObjectives"] call AIC_fnc_getSetting) isEqualTo true) then {
    private _max = [_cmd, "maxAutoObjectives"] call AIC_fnc_getSetting;

    private _objectives = _cmd get "objectives";
    private _have = { (_x getOrDefault ["source", ""]) isEqualTo "LOCATION" } count _objectives;
    if (_have >= _max) exitWith {};

    private _hq = _cmd getOrDefault ["hq", []];
    if (!(_hq isEqualType []) || { count _hq < 2 }) then { _hq = [worldSize / 2, worldSize / 2, 0]; };

    private _priorities = createHashMapFromArray [
        ["NameCityCapital", 3],
        ["NameCity", 2],
        ["Airport", 2.5],
        ["NameVillage", 1]
    ];
    private _radiusMul = createHashMapFromArray [
        ["NameCityCapital", 1.5],
        ["NameCity", 1.25],
        ["Airport", 1.5],
        ["NameVillage", 1]
    ];

    private _locations = nearestLocations [_hq, keys _priorities, worldSize * 1.5];

    {
        if (_have >= _max) exitWith {};
        private _loc = _x;
        private _type = type _loc;
        private _pos = locationPosition _loc;
        _pos = [_pos select 0, _pos select 1, 0];

        // skip if already covered by another objective (e.g. a module placed in the town)
        private _covered = ((_cmd get "objectives") findIf {
            (_x getOrDefault ["source", ""]) isNotEqualTo "BASE"
            && { ((_x getOrDefault ["pos", [0, 0, 0]]) distance2D _pos) < ((_x getOrDefault ["radius", 0]) max 50) }
        }) > -1;

        if (!_covered) then {
            private _name = text _loc;
            private _size = size _loc;
            private _locRadius = (_size select 0) max (_size select 1);
            private _radius = ((_locRadius max _defRadius) min (_defRadius * 2)) * (_radiusMul getOrDefault [_type, 1]);
            _radius = _radius min (_defRadius * 2.5);

            private _rec = [_cmd, _pos, _name, _radius, _priorities getOrDefault [_type, 1], "LOCATION"] call AIC_fnc_addObjective;
            if (count _rec > 0) then { _have = _have + 1; };
        };
    } forEach _locations;
};

// ---------------------------------------------------------------- 4. BASE_HQ
private _hqPos = _cmd getOrDefault ["hq", []];
if (
    _hqPos isEqualType [] && { count _hqPos >= 2 } && { (_hqPos select 0) isEqualType 0 } && { (_hqPos select 1) isEqualType 0 }
    && { count ([_cmd, AIC_BASE_ID] call AIC_fnc_getObjective) == 0 }
) then {
    // id = "<source>_<name>" = "BASE_HQ"; source BASE -> isBase true, owner = own side
    private _hqObj = [_cmd, _hqPos, "HQ", _defRadius min 300, 1, "BASE", true, 0] call AIC_fnc_addObjective;
    if (count _hqObj > 0) then { _hqObj set ["owner", _side]; };
};

private _count = count (_cmd getOrDefault ["objectives", []]);

["collectObjectives: %1 has %2 objectives", [_cmd getOrDefault ["side", sideUnknown], _count]] call AIC_fnc_log;

_count
