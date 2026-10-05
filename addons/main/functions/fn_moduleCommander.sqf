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

private _area = _logic getVariable ["objectArea", [250, 250, 0, false, -1]];
private _radius = ((_area select 0) max (_area select 1)) max 50;

private _groups = [];
{
    private _g = group _x;
    if (!isNull _g) then {_groups pushBackUnique _g};
} forEach (_units + synchronizedObjects _logic);

private _side = if (_sideIdx >= 0) then {
    [west, east, independent] select _sideIdx
} else {
    if (_groups isEqualTo []) then {sideUnknown} else {side (_groups select 0)}
};
if !(_side in [west, east, independent]) exitWith {
    "Commander module: sync some groups to it or pick a side." call CAI_fnc_log;
    diag_log "[CAI] Commander module has no groups and no side set.";
};

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

if (_groups isEqualTo []) then {
    _groups = allGroups select {
        side _x == _side
        && {(leader _x) distance2D _logic < _autoRadius}
        && {[_x] call _free}
        && {!(_x getVariable ["CAI_noQRF", false])}
    };
};

if (_groups isEqualTo []) exitWith {
    format ["Commander module (%1): no groups available.", _side] call CAI_fnc_log;
};

// Claim the groups right away so other commanders starting at the same moment can't take them.
{_x setVariable ["CAI_commander", _logic, true]} forEach _groups;

[_logic, _side, _groups, _mode, _radius, _reserve, _radio, _markers, [_fireLevel, _airSupport, _refit, _clear]] spawn CAI_fnc_commander;
