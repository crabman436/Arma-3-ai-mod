/*
    CAI_fnc_moduleCommander
    Starts an AI commander from the "Coordinated AI Commander" Eden module.
    Groups synced to the module are placed under its command. If nothing is
    synced, it takes every free AI group of the chosen side within the
    auto-assign radius. If a trigger is synced, the commander starts when the
    trigger fires.
*/

params [["_logic", objNull, [objNull]], ["_units", []], ["_activated", true]];

if (!isServer || {!_activated} || {isNull _logic}) exitWith {};
if (_logic getVariable ["CAI_cmdStarted", false]) exitWith {};
_logic setVariable ["CAI_cmdStarted", true];

if (isNil "CAI_cmdCounter") then {CAI_cmdCounter = 0};
CAI_cmdCounter = CAI_cmdCounter + 1;
_logic setVariable ["CAI_cmdId", CAI_cmdCounter];

private _mode = _logic getVariable ["Mode", 0];
private _sideIdx = _logic getVariable ["Side", -1];
private _reserve = ((_logic getVariable ["Reserve", 25]) max 0 min 90) / 100;
private _autoRadius = _logic getVariable ["AutoRadius", 2000];
private _radio = _logic getVariable ["Radio", true];
private _markers = _logic getVariable ["Markers", true];
private _fireLevel = _logic getVariable ["FireSupport", 1];
private _airSupport = _logic getVariable ["AirSupport", true];
private _refit = _logic getVariable ["Refit", true];
private _clear = _logic getVariable ["ClearBuildings", true];
private _para = _logic getVariable ["Paradrop", 0];
private _helo = _logic getVariable ["AirAssault", 0];
private _tempo = (_logic getVariable ["Tempo", 0]) max 0 min 2;
private _dispersed = (_logic getVariable ["Style", 0]) == 0;

private _area = _logic getVariable ["objectArea", [250, 250, 0, false, -1]];
private _radius = ((_area select 0) max (_area select 1)) max 50;

// Plan modules: a Staging Area and Attack Positions synced to the commander (or to one of
// its Objective modules) shape that attack; Objective modules are taken one after another.
private _planFor = {
    params ["_m"];
    private _synced = synchronizedObjects _m;
    private _st = _synced select {typeOf _x == "CAI_ModuleStaging"};
    private _staging = if (_st isEqualTo []) then {[]} else {
        private _p = getPosATL (_st select 0);
        [_p select 0, _p select 1, 0]
    };
    private _attack = (_synced select {typeOf _x == "CAI_ModuleAttackPos"}) apply {
        private _p = getPosATL _x;
        [_p select 0, _p select 1, 0]
    };
    [_staging, _attack]
};
private _objectives = [];
{
    if (typeOf _x == "CAI_ModuleObjective") then {
        private _a = _x getVariable ["objectArea", [200, 200, 0, false, -1]];
        private _p = getPosATL _x;
        ([_x] call _planFor) params ["_st", "_ap"];
        _objectives pushBack [_x getVariable ["Order", 1], _forEachIndex,
            [[_p select 0, _p select 1, 0], ((_a select 0) max (_a select 1)) max 50, _x getVariable ["LeaveGarrison", true], _st, _ap]];
    };
} forEach (synchronizedObjects _logic);
_objectives sort true;
_objectives = _objectives apply {_x select 2};
([_logic] call _planFor) params ["_stagingPos", "_attackPositions"];

private _groups = [];
{
    private _g = group _x;
    if (!isNull _g) then {_groups pushBackUnique _g};
} forEach (_units + ((synchronizedObjects _logic) select {_x isKindOf "AllVehicles"}));

private _side = if (_sideIdx >= 0) then {
    [west, east, independent] select _sideIdx
} else {
    if (_groups isEqualTo []) then {sideUnknown} else {side (_groups select 0)}
};
if !(_side in [west, east, independent]) exitWith {
    "Commander module: sync some groups to it or pick a side." call CAI_fnc_log;
    diag_log "[CAI] Commander module has no groups and no side set.";
};

// Empty helicopters, planes and trucks synced to the module get an AI crew for this
// side (infantry can't fly them, and an empty vehicle has no group to command).
{
    private _veh = _x;
    if (alive _veh
        && {_veh isKindOf "Air" || {_veh isKindOf "LandVehicle"}}
        && {!(_veh isKindOf "StaticWeapon")}
        && {!unitIsUAV _veh}
        && {(crew _veh findIf {alive _x}) < 0}
        && {locked _veh < 2}
    ) then {
        createVehicleCrew _veh;
        private _crew = crew _veh select {alive _x};
        if (_crew isNotEqualTo []) then {
            private _g = createGroup [_side, true];
            _crew joinSilent _g;
            _g selectLeader (effectiveCommander _veh);
            _groups pushBackUnique _g;
            format ["Commander module: crewed the empty %1", getText (configOf _veh >> "displayName")] call CAI_fnc_log;
        };
    };
} forEach (synchronizedObjects _logic);

// Like CAI_fnc_isValidGroup, but CARELESS groups (often used for parked helicopters
// and trucks) are allowed: the commander wakes them up.
private _free = {
    params ["_g"];
    private _l = leader _g;
    local _g
    && {alive _l}
    && {!isPlayer _l}
    && {!(_g getVariable ["CAI_exclude", false])}
    && {!unitIsUAV vehicle _l}
    && {(CAI_excludedTypes findIf {(vehicle _l) isKindOf _x}) < 0}
    && {isNull (_g getVariable ["CAI_commander", objNull])}
    && {(units _g findIf {isPlayer _x}) < 0}
};

_groups = _groups select {side _x == _side && {[_x] call _free}};

// Squads synced to a Garrison or Clear Area module have a job already.
private _moduleTasked = {
    params ["_g"];
    (units _g findIf {
        ((synchronizedObjects _x) findIf {typeOf _x in ["CAI_ModuleGarrison", "CAI_ModuleClear"]}) >= 0
    }) >= 0
};

if (_groups isEqualTo []) then {
    _groups = allGroups select {
        side _x == _side
        && {(leader _x) distance2D _logic < _autoRadius}
        && {[_x] call _free}
        && {!(_x getVariable ["CAI_noQRF", false])}
        && {(_x getVariable ["CAI_assist", []]) isEqualTo []}
        && {!(_x getVariable ["CAI_garrisoned", false])}
        && {!(_x getVariable ["CAI_clearing", false])}
        && {!([_x] call _moduleTasked)}
    };
};

if (_groups isEqualTo []) exitWith {
    format ["Commander module (%1): no groups available.", _side] call CAI_fnc_log;
};

// Claim the groups right away so other commanders starting at the same moment can't take them.
// A synced group that was out on quick reaction duty drops it: it's the commander's now.
{
    _x setVariable ["CAI_commander", _logic, true];
    _x setVariable ["CAI_assist", []];
} forEach _groups;

[_logic, _side, _groups, _mode, _radius, _reserve, _radio, _markers,
    [_fireLevel, _airSupport, _refit, _clear, _para, _helo, _tempo, _stagingPos, _attackPositions, _objectives, _dispersed]] spawn CAI_fnc_commander;
