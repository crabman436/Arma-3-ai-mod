/*
    CAI_fnc_cmdOrder
    Replaces a group's orders with a list of waypoints. Garrisoned units are
    released first.
    Params:
        0: GROUP
        1: ARRAY of waypoints, each [pos, type, behaviour, combat, speed, radius, (timeout)]
*/

params ["_grp", "_wps"];

if (isNull _grp || {_wps isEqualTo []}) exitWith {};

{
    if (alive _x && {!isPlayer _x}) then {
        _x enableAI "PATH";
        _x setUnitPos "AUTO";
    };
} forEach units _grp;

// Free any buildings this group was holding.
private _held = _grp getVariable ["CAI_garrisonBuildings", []];
if (_held isNotEqualTo []) then {
    private _key = format ["CAI_garrisonTaken_%1", side _grp];
    missionNamespace setVariable [_key, (missionNamespace getVariable [_key, []]) - _held];
    _grp setVariable ["CAI_garrisonBuildings", []];
};
_grp setVariable ["CAI_garrisoned", false];
_grp setVariable ["CAI_clearing", false];
_grp setVariable ["CAI_bounding", false];
[_grp] call CAI_fnc_clearWaypoints;
if (behaviour leader _grp == "CARELESS") then {_grp setBehaviour "AWARE"};

private _first = [];
{
    _x params ["_pos", ["_type", "MOVE"], ["_beh", "AWARE"], ["_combat", "YELLOW"], ["_speed", "NORMAL"], ["_radius", 50], ["_timeout", 0]];
    private _wp = [_grp, _pos, _type, _beh, _combat, _speed, _radius] call CAI_fnc_addWaypoint;
    if (_timeout > 0) then {_wp setWaypointTimeout [_timeout, _timeout, _timeout]};
    if (_forEachIndex == 0) then {_first = _wp};
} forEach _wps;

_grp setCurrentWaypoint _first;
