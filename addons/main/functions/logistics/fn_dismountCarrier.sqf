/*
    Function: AIC_fnc_dismountCarrier

    Description:
        Gets a group out of a vehicle that belongs to another group (server
        only). The one place that does so. Nobody jumps from a flying
        helicopter that still has a pilot: it can be told to land instead,
        and the caller tries again. Otherwise only a stopped vehicle or a
        landed helicopter is left, unless the caller forces it.
        Cargo groups of a running ride are handled by AIC_fnc_transportCycle,
        which calls this.

    Parameters:
        0: GROUP  - group to get out
        1: OBJECT - the vehicle it sits in
        2: BOOL   - (optional) tell a flying helicopter to land, default
                    false (false when its crew is busy with another ride)
        3: BOOL   - (optional) leave a moving ground vehicle, or a helicopter
                    going down without a pilot, default false

    Returns:
        BOOL - true if units were ordered out

    Example:
        [_group, _heli, true] call AIC_fnc_dismountCarrier;
*/

params [
    ["_group", grpNull, [grpNull]],
    ["_carrier", objNull, [objNull]],
    ["_land", false, [false]],
    ["_force", false, [false]]
];

if (!isServer) exitWith { false };
if (isNull _group || { isNull _carrier }) exitWith { false };

private _landed = [_carrier] call AIC_fnc_isLanded;
private _isAir = _carrier isKindOf "Air";
private _flying = _isAir && { !_landed } && { alive _carrier } && { canMove _carrier } && { alive (driver _carrier) };
if (_flying) exitWith {
    if (_land && { (time - (_carrier getVariable ["AIC_landOrderTime", -1e6])) > 45 }) then {
        _carrier setVariable ["AIC_landOrderTime", time];
        _carrier land "GET OUT";
    };
    false
};
if (!_landed && { !_force }) exitWith { false };

private _aboard = (units _group) select { alive _x && { objectParent _x isEqualTo _carrier } };
{
    unassignVehicle _x;
    doGetOut _x;
} forEach _aboard;
if (_aboard isNotEqualTo []) then {
    _aboard orderGetIn false;
    ["%1: group %2 dismounts %3", [side _group, groupId _group, typeOf _carrier]] call AIC_fnc_log;
};
_group leaveVehicle _carrier;

_aboard isNotEqualTo []
