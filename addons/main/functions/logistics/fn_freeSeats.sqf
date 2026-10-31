/*
    Function: AIC_fnc_freeSeats

    Description:
        Number of seats a vehicle has free for passengers of another group:
        empty cargo seats plus empty FFV (person turret) seats, each counted
        once from a single fullCrew enumeration, minus the seats the
        vehicle's own group needs for its members on foot that will climb
        back in. Seats already taken by members of the cargo group (a squad
        that sits in the vehicle before the ride is ordered) count as free.
        The one seat rule shared by AIC_fnc_findTransport (which vehicle to
        pick) and AIC_fnc_orderTransport (whether it still fits), so the
        first never picks a vehicle the second refuses.

    Parameters:
        0: OBJECT - vehicle
        1: GROUP  - the vehicle's (transport) group
        2: GROUP  - (optional) cargo group whose seated members count as free

    Returns:
        NUMBER - free passenger seats (may be negative)

    Example:
        if (([_veh, _tGroup] call AIC_fnc_freeSeats) >= count units _cargo) then { ... };
*/

params [
    ["_veh", objNull, [objNull]],
    ["_grp", grpNull, [grpNull]],
    ["_cargo", grpNull, [grpNull]]
];

if (isNull _veh) exitWith { 0 };

// one enumeration so every seat is counted once (an FFV seat is not
// also counted as a cargo seat)
private _free = {
    _x params ["_unit", "_role", "_cargoIdx", "_path", ["_isFFV", false]];
    (isNull _unit || { !isNull _cargo && { (group _unit) isEqualTo _cargo } })
    && { (_role == "cargo") || { _isFFV isEqualTo true } }
} count (fullCrew [_veh, "", true]);

// own members on foot that will climb back into this vehicle
private _ownNeed = if (isNull _grp) then { 0 } else {
    {
        alive _x && { isNull objectParent _x } && { (assignedVehicle _x) in [objNull, _veh] }
    } count (units _grp)
};

_free - _ownNeed
