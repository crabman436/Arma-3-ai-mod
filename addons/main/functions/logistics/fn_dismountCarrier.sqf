/*
    Function: AIC_fnc_dismountCarrier

    Description:
        Gets a group out of a vehicle that belongs to another group (server
        only). Only from a stopped vehicle or a landed helicopter: a flying
        helicopter can be told to land instead, nobody jumps. Cargo groups of
        a running ride are handled by AIC_fnc_transportCycle, not here.

    Parameters:
        0: GROUP  - group to get out
        1: OBJECT - the vehicle it sits in
        2: BOOL   - (optional) tell a flying helicopter to land, default
                    false (false when its crew is busy with another ride)

    Returns:
        BOOL - true if the units were ordered out

    Example:
        [_group, _heli, true] call AIC_fnc_dismountCarrier;
*/

params [
    ["_group", grpNull, [grpNull]],
    ["_carrier", objNull, [objNull]],
    ["_land", false, [false]]
];

if (!isServer) exitWith { false };
if (isNull _group || { isNull _carrier }) exitWith { false };

private _isAir = _carrier isKindOf "Air";
if !([_carrier] call AIC_fnc_isLanded) exitWith {
    if (_land && { _isAir } && { alive _carrier } && { alive (driver _carrier) }
        && { (time - (_carrier getVariable ["AIC_landOrderTime", -1e6])) > 45 }) then {
        _carrier setVariable ["AIC_landOrderTime", time];
        _carrier land "GET OUT";
    };
    false
};

private _aboard = (units _group) select { alive _x && { objectParent _x isEqualTo _carrier } };
if (_aboard isEqualTo []) exitWith { false };

{
    unassignVehicle _x;
    doGetOut _x;
} forEach _aboard;
_aboard orderGetIn false;
_group leaveVehicle _carrier;

["%1: group %2 dismounts %3", [side _group, groupId _group, typeOf _carrier]] call AIC_fnc_log;

true
