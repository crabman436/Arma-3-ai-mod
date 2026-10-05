/*
    CAI_fnc_saveHome
    Remembers where a group was and what it was doing before it is sent away,
    so it can go back afterwards. Only the first call is kept.
    Params: 0: GROUP
*/

params ["_grp"];

if ((_grp getVariable ["CAI_home", []]) isNotEqualTo []) exitWith {};

private _leader = leader _grp;
private _orig = [];
private _cur = currentWaypoint _grp;
if (_cur < count waypoints _grp) then {
    _orig = [waypointType [_grp, _cur], waypointPosition [_grp, _cur]];
};
private _landed = (vehicle _leader) isKindOf "Air" && {isTouchingGround vehicle _leader};

_grp setVariable ["CAI_home", [getPosATL _leader, _orig, behaviour _leader, combatMode _grp, _landed]];
