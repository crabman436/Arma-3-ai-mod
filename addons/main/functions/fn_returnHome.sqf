/*
    CAI_fnc_returnHome
    Ends QRF duty: the group goes back to where it came from and resumes its
    original order (guard, sentry, loiter...) if it had one.
    Params: 0: GROUP
*/

params ["_grp"];

_grp setVariable ["CAI_assist", []];
_grp setVariable ["CAI_busy", false];
_grp setVariable ["CAI_inTransit", false];

private _home = _grp getVariable ["CAI_home", []];
if (_home isEqualTo [] || {!alive leader _grp}) exitWith {};
_home params ["_pos", "_orig", "_behaviour", "_combat", "_landed"];

[_grp] call CAI_fnc_clearWaypoints;
private _wp = [_grp, _pos, "MOVE", "AWARE", _combat, "NORMAL", 50] call CAI_fnc_addWaypoint;
if (_landed) then {
    _wp setWaypointStatements ["true", "(vehicle this) land 'LAND'"];
};
if (_orig isNotEqualTo []) then {
    _orig params ["_type", "_origPos"];
    [_grp, _origPos, _type, _behaviour, _combat, "NORMAL", 50] call CAI_fnc_addWaypoint;
};
_grp setCurrentWaypoint _wp;

format ["%1 returning to its position", groupId _grp] call CAI_fnc_log;
