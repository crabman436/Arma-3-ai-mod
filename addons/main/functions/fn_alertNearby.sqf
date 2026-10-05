/*
    CAI_fnc_alertNearby
    Called when a soldier dies. Nearby friendly groups go on alert and get a
    rough idea of where the shooter is.
    Params: 0: OBJECT killed unit, 1: OBJECT killer
*/

params ["_unit", "_killer"];

private _side = side group _unit;
if !(_side in [west, east, independent]) exitWith {};
private _pos = getPosATL _unit;
private _shooter = vehicle _killer;
private _hostileShooter = !isNull _shooter && {alive _shooter} && {((side group _killer) getFriend _side) < 0.6};

{
    if (local _x
        && {(_side getFriend side _x) >= 0.6}
        && {[_x] call CAI_fnc_isValidGroup}
        && {(leader _x) distance2D _pos < CAI_alertRadius}
    ) then {
        if (behaviour leader _x == "SAFE") then {_x setBehaviour "AWARE"};
        if (_hostileShooter) then {
            private _k = linearConversion [0, 800, (leader _x) distance _shooter, 2, 1, true];
            _x reveal [_shooter, _k];
        };
    };
} forEach allGroups;
