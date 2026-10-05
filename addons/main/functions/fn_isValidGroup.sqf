/*
    CAI_fnc_isValidGroup
    Returns true if a group should be driven by Coordinated AI.
    Params: 0: GROUP
*/

params [["_grp", grpNull, [grpNull]]];

if (isNull _grp) exitWith {false};
private _leader = leader _grp;
if (isNull _leader || {!alive _leader}) exitWith {false};
if (isPlayer _leader) exitWith {false};
if (_grp getVariable ["CAI_exclude", false]) exitWith {false};
if !(side _grp in [west, east, independent]) exitWith {false};
if (behaviour _leader == "CARELESS" && {!(_grp getVariable ["CAI_busy", false])}) exitWith {false};

private _veh = vehicle _leader;
if (unitIsUAV _veh) exitWith {false};
if ((CAI_excludedTypes findIf {_veh isKindOf _x}) >= 0) exitWith {false};

true
