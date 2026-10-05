/*
    CAI_fnc_clearWaypoints
    Removes all waypoints of a group and cancels individual move orders.
    Params: 0: GROUP
*/

params ["_grp"];

for "_i" from (count waypoints _grp - 1) to 0 step -1 do {
    deleteWaypoint [_grp, _i];
};

private _leader = leader _grp;
{
    if (alive _x && {!isPlayer _x} && {isNull objectParent _x} && {_x != _leader}) then {
        _x doFollow _leader;
    };
} forEach units _grp;
