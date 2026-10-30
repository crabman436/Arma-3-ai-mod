/*
    Function: AIC_fnc_addObjective

    Description:
        Adds an objective record to a commander's "objectives" list.
        The objective id is "<source>_<name>" (or "<source>_<grid>" when the
        name is empty). Deduplication:
          - an objective with the same id at (roughly) the same place
            (within the larger of both radii) is returned unchanged
            (its priority is raised if the new priority is higher);
          - an objective with the same id somewhere else (two map locations
            sharing a name) gets the grid appended: "<source>_<name>_<grid>".
        New records start with owner sideUnknown and score 0; the real owner
        is computed by AIC_fnc_updateObjectives. Exception: records with
        source "BASE" (BASE_HQ and the commander's own "aic_base_<side>"
        markers) start owned by the commander's side.
        Logistics keys: "isBase" (bool, default false) and "garrison"
        (desired garrison power override, default 0 = auto). When an
        existing record is returned, isBase is raised to true and a
        garrison override > 0 is applied if the new call asks for it.
        Maintains the commander key "objectiveIndex" (HashMap id -> record,
        same records as "objectives"); dedup lookups use it, and every other
        reader looks objectives up with AIC_fnc_getObjective.

    Parameters:
        0: HASHMAP - commander
        1: ARRAY   - position (2D or 3D, treated as ATL; z is forced to 0)
        2: STRING  - display name ("" -> grid reference is used)
        3: NUMBER  - capture radius (<= 0 -> commander setting "objectiveRadius")
        4: NUMBER  - priority (<= 0 -> 1)
        5: STRING  - source: "MODULE", "MARKER", "LOCATION" or "BASE"
        6: BOOL    - (optional) isBase, default false (forced true for "BASE")
        7: NUMBER  - (optional) desired garrison power, default 0 (= auto)

    Returns:
        HASHMAP - the objective record (new or existing),
                  empty HashMap on invalid input

    Example:
        private _obj = [_cmd, getMarkerPos "aic_obj_1", "Hill 205", 250, 2, "MARKER"] call AIC_fnc_addObjective;
        systemChat (_obj get "id"); // "MARKER_Hill 205"
        private _hqObj = [_cmd, _cmd get "hq", "HQ", 0, 1, "BASE", true, 0] call AIC_fnc_addObjective; // id "BASE_HQ"
*/

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_pos", [], [[]], [2, 3]],
    ["_name", "", [""]],
    ["_radius", 0, [0]],
    ["_priority", 1, [0]],
    ["_source", "MODULE", [""]],
    ["_isBase", false, [false]],
    ["_garrison", 0, [0]]
];

if (count _cmd == 0) exitWith { createHashMap };
if (count _pos < 2) exitWith { createHashMap };
if !((_pos select 0) isEqualType 0 && { (_pos select 1) isEqualType 0 }) exitWith { createHashMap };

private _posATL = [_pos select 0, _pos select 1, 0];

if (_radius <= 0) then {
    _radius = [_cmd, "objectiveRadius"] call AIC_fnc_getSetting;
    if (isNil "_radius" || { !(_radius isEqualType 0) } || { _radius <= 0 }) then { _radius = 300; };
};
if (_priority <= 0) then { _priority = 1; };

_source = toUpperANSI _source;
if !(_source in ["MODULE", "MARKER", "LOCATION", "BASE"]) then { _source = "MODULE"; };
if (_source isEqualTo "BASE") then { _isBase = true; };
_garrison = _garrison max 0;

private _grid = mapGridPosition _posATL;
if (_name isEqualTo "") then { _name = _grid; };

private _objectives = _cmd getOrDefault ["objectives", []];
if !(_objectives isEqualType []) then {
    _objectives = [];
};
_cmd set ["objectives", _objectives];

// id -> record index kept in sync with "objectives" (O(1) lookups for every
// reader via AIC_fnc_getObjective); rebuilt here if it is missing or stale
private _index = _cmd getOrDefault ["objectiveIndex", createHashMap];
if (!(_index isEqualType createHashMap) || { (count _index) != (count _objectives) }) then {
    _index = createHashMap;
    {
        if (_x isEqualType createHashMap) then { _index set [_x getOrDefault ["id", ""], _x]; };
    } forEach _objectives;
};
_cmd set ["objectiveIndex", _index];

// returns the existing record with this id or an empty HashMap
private _fnc_findById = {
    params ["_id"];
    _index getOrDefault [_id, createHashMap]
};

// same objective if within the larger of both capture radii
private _fnc_samePlace = {
    params ["_rec"];
    private _recPos = _rec getOrDefault ["pos", [0, 0, 0]];
    private _recRad = _rec getOrDefault ["radius", 0];
    (_recPos distance2D _posATL) <= (_recRad max _radius)
};

private _id = format ["%1_%2", _source, _name];
private _existing = [_id] call _fnc_findById;

if (count _existing > 0) then {
    if ([_existing] call _fnc_samePlace) exitWith {};
    // same name, different place -> disambiguate with the grid reference
    _id = format ["%1_%2_%3", _source, _name, _grid];
    _existing = [_id] call _fnc_findById;
    if (count _existing > 0 && { !([_existing] call _fnc_samePlace) }) then {
        // extremely unlikely: same name + same grid square but outside radius
        private _n = 2;
        while { count ([format ["%1_%2", _id, _n]] call _fnc_findById) > 0 } do { _n = _n + 1; };
        _id = format ["%1_%2", _id, _n];
        _existing = createHashMap;
    };
};

if (count _existing > 0) exitWith {
    if (_priority > (_existing getOrDefault ["priority", 0])) then {
        _existing set ["priority", _priority];
    };
    if (_isBase) then { _existing set ["isBase", true]; };
    if !("isBase" in _existing) then { _existing set ["isBase", false]; };
    if (_garrison > 0) then { _existing set ["garrison", _garrison]; };
    if !("garrison" in _existing) then { _existing set ["garrison", 0]; };
    _existing
};

private _record = createHashMapFromArray [
    ["id", _id],
    ["name", _name],
    ["pos", _posATL],
    ["radius", _radius],
    ["priority", _priority],
    ["owner", if (_source isEqualTo "BASE") then { _cmd getOrDefault ["side", sideUnknown] } else { sideUnknown }],
    ["source", _source],
    ["score", 0],
    ["isBase", _isBase],
    ["garrison", _garrison]
];

_objectives pushBack _record;
_index set [_id, _record];

if (!isNil "AIC_ns" && { AIC_ns getOrDefault ["debug", false] isEqualTo true }) then {
    ["addObjective: %1 added '%2' (%3) at %4 r %5 p %6 base %7 garrison %8", [
        _cmd getOrDefault ["side", sideUnknown], _name, _id, _grid, _radius, _priority, _isBase, _garrison
    ]] call AIC_fnc_log;
};

_record
