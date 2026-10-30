/*
    Function: AIC_fnc_updateObjectives

    Description:
        Refreshes the "owner" of each of the commander's objectives.
        For every objective the alive units inside its radius are counted per
        side (nearEntities: infantry on foot plus the alive crew of land
        vehicles, ships and landed aircraft; captives ignored; side = side of
        the unit's group; civilians only count if a civilian commander
        exists). Ownership:
          - one side has more than twice the units of all other sides
            together -> that side owns it;
          - nobody present -> previous owner is kept;
          - otherwise (contested) -> sideUnknown.
        Bases ("isBase" true, including "BASE_HQ") are sticky: they keep
        their owner while nobody / a mixed force / a friendly side is there,
        and only change hands when an enemy of the current owner actually
        holds them (2:1 rule). A base without an owner (sideUnknown) that
        has source "BASE" (BASE_HQ, own "aic_base_<side>" markers) falls
        back to the commander's side unless an enemy holds it.
        Also picks up "aic_obj*" and own "aic_base_<side>*" markers created
        after the commander started, and a missing "BASE_HQ" (re-runs
        AIC_fnc_collectObjectives if one is found).

    Parameters:
        0: HASHMAP - commander

    Returns:
        ARRAY - the commander's objective records

    Example:
        [_cmd] call AIC_fnc_updateObjectives;
        { systemChat format ["%1: %2", _x get "name", _x get "owner"] } forEach (_cmd get "objectives");
*/

params [["_cmd", createHashMap, [createHashMap]]];

if (count _cmd == 0) exitWith { [] };

private _objectives = _cmd getOrDefault ["objectives", []];
if !(_objectives isEqualType []) then {
    _objectives = [];
    _cmd set ["objectives", _objectives];
};

// ------------------------------------------------------------ late markers
private _cmdSide = _cmd getOrDefault ["side", sideUnknown];
private _markerObjs = _objectives select { (_x getOrDefault ["source", ""]) isEqualTo "MARKER" };
private _baseObjs = _objectives select { (_x getOrDefault ["source", ""]) isEqualTo "BASE" };
private _basePrefix = "aic_base_" + toLower str _cmdSide;
private _newMarker = allMapMarkers findIf {
    private _m = _x;
    private _lower = toLower _m;
    private _mPos = getMarkerPos _m;
    (((_lower find "aic_obj") == 0) && {
        (_markerObjs findIf { ((_x getOrDefault ["pos", [0, 0, 0]]) distance2D _mPos) <= ((_x getOrDefault ["radius", 0]) max 1) }) < 0
    }) || {
        (_cmdSide in [west, east, independent, civilian]) && { (_lower find _basePrefix) == 0 } && {
            (_baseObjs findIf { ((_x getOrDefault ["pos", [0, 0, 0]]) distance2D _mPos) <= ((_x getOrDefault ["radius", 0]) max 1) }) < 0
        }
    }
};
private _hqMissing = count ([_cmd, "BASE_HQ"] call AIC_fnc_getObjective) == 0;
if (_newMarker > -1 || _hqMissing) then {
    [_cmd] call AIC_fnc_collectObjectives;
    _objectives = _cmd getOrDefault ["objectives", []];
};

if (_objectives isEqualTo []) exitWith { _objectives };

// ------------------------------------------------------------ ownership
private _countSides = [west, east, independent];
if (!isNil "AIC_commanders" && { AIC_commanders isEqualType createHashMap } && { count (AIC_commanders getOrDefault [civilian, createHashMap]) > 0 }) then {
    _countSides pushBack civilian;
};

private _entityTypes = ["CAManBase", "LandVehicle", "Ship", "Air"];

{
    private _obj = _x;
    private _pos = _obj getOrDefault ["pos", []];
    if (_pos isEqualType [] && { count _pos >= 2 }) then {
        private _radius = (_obj getOrDefault ["radius", 300]) max 10;
        private _counts = createHashMap; // side -> unit count

        {
            private _ent = _x;
            if (_ent isKindOf "CAManBase") then {
                if (alive _ent && { !captive _ent }) then {
                    private _s = side group _ent;
                    if (_s in _countSides) then { _counts set [_s, (_counts getOrDefault [_s, 0]) + 1]; };
                };
            } else {
                // aircraft only hold ground when landed
                if (alive _ent && { !(_ent isKindOf "Air") || { isTouchingGround _ent } }) then {
                    {
                        if (alive _x && { !captive _x }) then {
                            private _s = side group _x;
                            if (_s in _countSides) then { _counts set [_s, (_counts getOrDefault [_s, 0]) + 1]; };
                        };
                    } forEach (crew _ent);
                };
            };
        } forEach ([_pos select 0, _pos select 1, 0] nearEntities [_entityTypes, _radius]);

        private _total = 0;
        private _topSide = sideUnknown;
        private _topCount = 0;
        {
            _total = _total + _y;
            if (_y > _topCount) then { _topCount = _y; _topSide = _x; };
        } forEach _counts;

        private _prevOwner = _obj getOrDefault ["owner", sideUnknown];
        private _owner = call {
            if (_total == 0) exitWith { _prevOwner };
            if (_topCount > 2 * (_total - _topCount)) exitWith { _topSide };
            sideUnknown
        };

        // bases only change hands when an enemy actually holds them
        if ((_obj getOrDefault ["isBase", false]) isEqualTo true) then {
            private _holder = _prevOwner;
            if (_holder isEqualTo sideUnknown && { (_obj getOrDefault ["source", ""]) isEqualTo "BASE" }) then {
                _holder = _cmdSide;
            };
            _owner = call {
                if (_owner isEqualTo sideUnknown) exitWith { _holder };
                if (_holder isEqualTo sideUnknown) exitWith { _owner };
                if (_owner isEqualTo _holder) exitWith { _holder };
                // a different side holds it 2:1 - only an enemy of the holder takes it
                if ((_holder getFriend _owner) < 0.6) exitWith { _owner };
                _holder
            };
        };

        if (_owner isNotEqualTo _prevOwner) then {
            _obj set ["owner", _owner];
            if (!isNil "AIC_debug" && { AIC_debug isEqualTo true }) then {
                ["updateObjectives: %1 '%2' owner %3 -> %4 (%5)", [
                    _cmd getOrDefault ["side", sideUnknown], _obj getOrDefault ["name", ""], _prevOwner, _owner, _counts toArray false
                ]] call AIC_fnc_log;
            };
        };
    };
} forEach _objectives;

_objectives
