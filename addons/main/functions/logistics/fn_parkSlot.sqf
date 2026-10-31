/*
 * Name: AIC_fnc_parkSlot
 * Description:
 *   A parking place at a base for a vehicle group (server only, setting
 *   "useVehicleParks"). Each base lays out, the first time it is asked, a
 *   motor pool on open flat ground (AIC_fnc_bestPlace): up to 20 places in rows for ground
 *   vehicles ("parkSlots") and up to 6 for helicopters ("heliSlots"), each
 *   helicopter place with an invisible helipad so the pilot lands there
 *   (base key "heliPads", deleted by AIC_fnc_removeCommander).
 *   A group keeps its place while its record "home" is this base, also
 *   while it is away on a ride or an attack; a group that moves home gives
 *   it up.
 *
 * Parameters:
 *   0: HASHMAP - commander
 *   1: GROUP   - vehicle group
 *   2: HASHMAP - base objective record
 *   3: BOOL    - (optional) helicopter place, default false
 *
 * Returns:
 *   ARRAY - [x, y, 0], [] if there is no base, no park or no free place
 *
 * Example:
 *   private _slot = [_cmd, _group, _baseRecord, true] call AIC_fnc_parkSlot;
 */

params [
    ["_cmd", createHashMap, [createHashMap]],
    ["_group", grpNull, [grpNull]],
    ["_obj", createHashMap, [createHashMap]],
    ["_isHeli", false, [false]]
];

if (!isServer || {isNull _group} || {count _obj == 0}) exitWith {[]};
if !((_obj getOrDefault ["isBase", false]) isEqualTo true) exitWith {[]};
if !(([_cmd, "useVehicleParks"] call AIC_fnc_getSetting) isEqualTo true) exitWith {[]};

private _key = ["parkSlots", "heliSlots"] select _isHeli;

// --- lay the park out once ------------------------------------------------------
if !(_key in _obj) then {
    private _c = _obj get "pos";
    _c = [_c select 0, _c select 1, 0];
    private _size = [14, 40] select _isHeli;
    private _cols = [5, 3] select _isHeli;
    private _rows = [4, 2] select _isHeli;
    private _reach = ((_obj getOrDefault ["radius", 300]) min 250) max 60;
    // open flat ground by the engine's terrain scoring, else the old safe-spot search
    private _centre = [_c, _reach, "meadow - forest - 2*trees - 3*houses - 10*sea - 2*hills", _size] call AIC_fnc_bestPlace;
    if (_centre isEqualTo []) then {
        _centre = [_c, 30, _reach, 20, 0, 0.15, 0, [], [_c, _c]] call BIS_fnc_findSafePos;
    };
    private _dir = _c getDir _centre;
    private _slots = [];
    for "_r" from 0 to (_rows - 1) do {
        for "_col" from 0 to (_cols - 1) do {
            private _p = (_centre getPos [(_r - (_rows - 1) / 2) * _size, _dir]) getPos [(_col - (_cols - 1) / 2) * _size, _dir + 90];
            _p = [_p select 0, _p select 1, 0];
            if (!surfaceIsWater _p && {(_p isFlatEmpty [_size * 0.4, -1, 0.3, _size * 0.4, 0, false]) isNotEqualTo []}) then {
                _slots pushBack _p;
                if (_isHeli) then {
                    private _pads = _obj getOrDefault ["heliPads", []];
                    _pads pushBack (createVehicle ["Land_HelipadEmpty_F", _p, [], 0, "CAN_COLLIDE"]);
                    _obj set ["heliPads", _pads];
                };
            };
        };
    };
    _obj set [_key, _slots];
    ["%1: %2 park at '%3' with %4 places", [
        _cmd getOrDefault ["side", sideUnknown], ["vehicle", "helicopter"] select _isHeli,
        _obj getOrDefault ["name", ""], count _slots
    ]] call AIC_fnc_log;
};

private _slots = _obj get _key;
if (_slots isEqualTo []) exitWith {[]};

// --- find its place --------------------------------------------------------------
private _claimKey = _key + "Claims";
private _claims = _obj getOrDefault [_claimKey, createHashMap];
_obj set [_claimKey, _claims];
private _groupData = _cmd getOrDefault ["groupData", createHashMap];
private _id = _obj getOrDefault ["id", ""];
private _rec = _groupData getOrDefault [hashValue _group, createHashMap];

private _free = -1;
private _own = -1;
{
    private _holder = _claims getOrDefault [_forEachIndex, grpNull];
    if (_holder isEqualTo _group) exitWith {_own = _forEachIndex};
    if (_free < 0) then {
        private _hRec = if (isNull _holder) then {createHashMap} else {_groupData getOrDefault [hashValue _holder, createHashMap]};
        if (
            isNull _holder
            || {({alive _x} count (units _holder)) == 0}
            || {(_hRec getOrDefault ["home", ""]) isNotEqualTo _id}
        ) then {_free = _forEachIndex};
    };
} forEach _slots;

private _index = if (_own >= 0) then {_own} else {_free};
if (_index < 0) exitWith {[]};

_claims set [_index, _group];
// a helicopter is told to land on its own pad (AIC_fnc_monitorOrders, RTB)
if (_isHeli) then {
    _rec set ["parkPad", (_obj getOrDefault ["heliPads", []]) param [_index, objNull]];
};
+(_slots select _index)
