/*
    CAI_fnc_clearWaypoints
    Removes all waypoints of a group and cancels individual move orders.
    Params: 0: GROUP
*/

params ["_grp"];

for "_i" from (count waypoints _grp - 1) to 0 step -1 do {
    deleteWaypoint [_grp, _i];
};

// Cancel individual orders (doMove/doStop). doFollow on the leader himself
// releases a doStop so he follows the new waypoints again.
private _leader = leader _grp;
{
    if (alive _x && {!isPlayer _x} && {isNull objectParent _x}) then {
        _x doFollow _leader;
    };
} forEach units _grp;
