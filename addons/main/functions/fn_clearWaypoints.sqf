/*
    CAI_fnc_clearWaypoints
    Removes all waypoints of a group and cancels individual move orders.
    Every call counts as new orders (CAI_orderId goes up).
    Params: 0: GROUP
*/

params ["_grp"];

// New orders: scripts still driving this group's soldiers (fire & maneuver) see this and stop.
_grp setVariable ["CAI_orderId", (_grp getVariable ["CAI_orderId", 0]) + 1];

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
