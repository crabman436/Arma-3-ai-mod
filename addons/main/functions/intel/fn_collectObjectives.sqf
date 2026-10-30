/*
    Function: AIC_fnc_collectObjectives

    Description:
        Builds (or extends) a commander's objective list from three sources,
        in this order:
          1. Eden objective modules stored in AIC_objectiveModules
             (logic variables "Name", "Radius", "Priority").
          2. Map markers whose name starts with "aic_obj" (case-insensitive).
             Name = marker text (or marker name if no text). Area markers
             (ELLIPSE / RECTANGLE) use their largest half-size as radius,
             other markers use the "objectiveRadius" setting. Priority 1.5,
             or the number after "_p" in the marker name if present
             (e.g. "aic_obj_bridge_p3" -> priority 3).
          3. If setting "autoObjectives": map locations of type
             NameCityCapital (priority 3), NameCity (2), Airport (2.5) and
             NameVillage (1), nearest to the commander HQ, until the commander
             holds "maxAutoObjectives" LOCATION objectives. A location is
             skipped if an existing objective already covers its centre.
        Safe to call repeatedly: AIC_fnc_addObjective dedupes by id.

    Parameters:
        0: HASHMAP - commander

    Returns:
        NUMBER - number of objectives the commander now has

    Example:
        [_cmd] call AIC_fnc_collectObjectives;
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith { 0 };

if !((_cmd getOrDefault ["objectives", []]) isEqualType []) then { _cmd set ["objectives", []]; };
if !("objectives" in _cmd) then { _cmd set ["objectives", []]; };

private _defRadius = [_cmd, "objectiveRadius"] call AIC_fnc_getSetting;
if (isNil "_defRadius" || { !(_defRadius isEqualType 0) } || { _defRadius <= 0 }) then { _defRadius = 300; };

// ---------------------------------------------------------------- 1. modules
if (!isNil "AIC_objectiveModules" && { AIC_objectiveModules isEqualType [] }) then {
    {
        private _logic = _x;
        if (!isNull _logic) then {
            private _name = _logic getVariable ["Name", ""];
            if !(_name isEqualType "") then { _name = str _name; };
            private _radius = _logic getVariable ["Radius", _defRadius];
            if (_radius isEqualType "") then { _radius = parseNumber _radius; };
            if !(_radius isEqualType 0) then { _radius = _defRadius; };
            private _priority = _logic getVariable ["Priority", 2];
            if (_priority isEqualType "") then { _priority = parseNumber _priority; };
            if !(_priority isEqualType 0) then { _priority = 2; };
            [_cmd, getPosATL _logic, _name, _radius, _priority, "MODULE"] call AIC_fnc_addObjective;
        };
    } forEach AIC_objectiveModules;
};

// ---------------------------------------------------------------- 2. markers
{
    private _marker = _x;
    private _lower = toLower _marker;
    if ((_lower find "aic_obj") == 0) then {
        private _name = markerText _marker;
        if (_name isEqualTo "") then { _name = _marker; };

        private _radius = _defRadius;
        if ((markerShape _marker) in ["ELLIPSE", "RECTANGLE"]) then {
            private _size = markerSize _marker;
            _radius = ((_size select 0) max (_size select 1)) max 25;
        };

        private _priority = 1.5;
        // last "_p<number>" in the name
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

        [_cmd, getMarkerPos _marker, _name, _radius, _priority, "MARKER"] call AIC_fnc_addObjective;
    };
} forEach allMapMarkers;

// ---------------------------------------------------------------- 3. locations
if (([_cmd, "autoObjectives"] call AIC_fnc_getSetting) isEqualTo true) then {
    private _max = [_cmd, "maxAutoObjectives"] call AIC_fnc_getSetting;
    if !(_max isEqualType 0) then { _max = 12; };

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
            ((_x getOrDefault ["pos", [0, 0, 0]]) distance2D _pos) < ((_x getOrDefault ["radius", 0]) max 50)
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

private _count = count (_cmd getOrDefault ["objectives", []]);

["collectObjectives: %1 has %2 objectives", [_cmd getOrDefault ["side", sideUnknown], _count]] call AIC_fnc_log;

_count
