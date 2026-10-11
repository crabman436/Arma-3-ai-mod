/*
    CAI_fnc_releaseGroup
    Ends whatever held a group in place: soldiers can move again (PATH on,
    stance back to auto, no fixed watch point) and the buildings it held as a
    garrison are free for other squads.
    Params: 0: GROUP
*/

params ["_grp"];

if (isNull _grp) exitWith {};

{
    if (alive _x && {!isPlayer _x}) then {
        _x enableAI "PATH";
        _x setUnitPos "AUTO";
        _x doWatch objNull;
    };
} forEach units _grp;

private _held = _grp getVariable ["CAI_garrisonBuildings", []];
if (_held isNotEqualTo []) then {
    private _key = format ["CAI_garrisonTaken_%1", side _grp];
    missionNamespace setVariable [_key, (missionNamespace getVariable [_key, []]) - _held];
    _grp setVariable ["CAI_garrisonBuildings", []];
};
_grp setVariable ["CAI_garrisoned", false];
