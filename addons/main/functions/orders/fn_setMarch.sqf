/*
 * Name: AIC_fnc_setMarch
 * Description:
 *   Puts a group on the march, or takes it off again. On the march:
 *     - no automatic combat mode (disableAI "AUTOCOMBAT"): the engine
 *       otherwise drops a group into COMBAT the moment it sees an enemy and
 *       it crawls the rest of the way. The group still fires back and still
 *       follows its waypoints' own behaviour;
 *     - vehicles the group drives stay on roads (forceFollowRoad), in column
 *       at AIC_CONVOY_SEPARATION, and a convoy of several vehicles has its
 *       lead vehicle held to AIC_CONVOY_SPEED so the others keep up.
 *   Off the march everything is back to default. The state is kept in the
 *   group variable "AIC_marching". AIC_fnc_issueOrder starts a march for
 *   long moves, AIC_fnc_monitorOrders ends it near the target, at the
 *   assembly area, or on contact.
 *
 * Parameters:
 *   0: GROUP - group
 *   1: BOOL  - true: on the march, false: off
 *
 * Returns:
 *   BOOL - the new state
 *
 * Example:
 *   [_group, true] call AIC_fnc_setMarch;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [
    ["_group", grpNull, [grpNull]],
    ["_on", false, [false]]
];

if (isNull _group) exitWith {false};
if ((_group getVariable ["AIC_marching", false]) isEqualTo _on) exitWith {_on};
_group setVariable ["AIC_marching", _on];

private _vehicles = [];
{
    if (alive _x && {!isPlayer _x}) then {
        if (_on) then {_x disableAI "AUTOCOMBAT"} else {_x enableAI "AUTOCOMBAT"};
        private _veh = objectParent _x;
        if (!isNull _veh && {(group (driver _veh)) isEqualTo _group} && {_veh isKindOf "LandVehicle"} && {!(_veh isKindOf "StaticWeapon")}) then {
            _vehicles pushBackUnique _veh;
        };
    };
} forEach (units _group);
// off the march: every vehicle this march limited, also one whose crew died
// or got out since (its road / speed limits stay on it for whoever drives it
// next); never a vehicle another group drives
if (!_on) then {
    {
        if (!isNull _x && {alive _x} && {isNull (driver _x) || {!alive (driver _x)} || {(group (driver _x)) isEqualTo _group}}) then {
            _vehicles pushBackUnique _x;
        };
    } forEach (_group getVariable ["AIC_marchVehicles", []]);
    _group setVariable ["AIC_marchVehicles", nil];
};

if (_vehicles isEqualTo []) exitWith {_on};

{
    _x forceFollowRoad _on;
    // documented reset: a negative value does not clear the cap (it caps at 1 km/h)
    _x limitSpeed (2 * getNumber (configOf _x >> "maxSpeed"));
    if (_on) then {_x setConvoySeparation AIC_CONVOY_SEPARATION};
} forEach _vehicles;
// the convoy follows its lead vehicle (one of its own land vehicles)
if (_on && {count _vehicles > 1}) then {
    private _lead = vehicle (leader _group);
    if !(_lead in _vehicles) then {_lead = _vehicles select 0};
    _lead limitSpeed AIC_CONVOY_SPEED;
};
if (_on) then {_group setVariable ["AIC_marchVehicles", _vehicles]};

_on
