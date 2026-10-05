/*
    CAI_fnc_grabVehicles
    Lets an infantry group take nearby empty, unlocked vehicles so it can
    drive to the fight. Vehicles are added to the group, and the AI mounts
    up and drives on its own.
    Params: 0: GROUP, 1: BOOL dry run (only check, don't take)
    Returns: BOOL - enough seats were found
*/

params ["_grp", ["_dryRun", false]];

private _leader = leader _grp;
private _need = {alive _x && {vehicle _x == _x}} count units _grp;
if (_need == 0) exitWith {false};

private _cands = (_leader nearEntities [["Car", "Tank", "Wheeled_APC_F"], 150]) select {
    alive _x
    && {canMove _x}
    && {fuel _x > 0.1}
    && {locked _x < 2}
    && {({alive _x} count crew _x) == 0}
    && {!(_x getVariable ["CAI_claimed", false])}
};
if (_cands isEqualTo []) exitWith {false};

private _sorted = [];
{_sorted pushBack [_x distance _leader, _forEachIndex, _x]} forEach _cands;
_sorted sort true;

private _seats = 0;
private _take = [];
{
    private _v = _x select 2;
    if (_seats < _need) then {
        _seats = _seats + count (fullCrew [_v, "", true]);
        _take pushBack _v;
    };
} forEach _sorted;

if (_seats < _need) exitWith {false};
if (_dryRun) exitWith {true};

{
    _grp addVehicle _x;
    _x setVariable ["CAI_claimed", true, true];
} forEach _take;

true
