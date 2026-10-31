/*
    Function: AIC_fnc_isLanded

    Description:
        Tells whether passengers can safely get in or out of a vehicle now.
        Helicopters count once they touch the ground or hang slowly just above
        it: land "GET IN" and "GET OUT" only make the pilot hover low, so
        isTouchingGround alone can stay false for the whole stop. Every other
        vehicle counts once it has stopped.

    Parameters:
        0: OBJECT - vehicle

    Returns:
        BOOL - true if the vehicle is landed / stopped (false for objNull)

    Example:
        if ([_heli] call AIC_fnc_isLanded) then { doGetOut _unit; };
*/

params [["_veh", objNull, [objNull]]];

if (isNull _veh) exitWith { false };
if !(_veh isKindOf "Air") exitWith { (abs (speed _veh)) < 3 };

isTouchingGround _veh || { (((getPos _veh) select 2) < 3.5) && { (abs (speed _veh)) < 15 } }
