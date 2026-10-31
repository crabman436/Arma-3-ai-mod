/*
 * Name: AIC_fnc_vehicleArmament
 * Description:
 *   How heavily a vehicle is armed, from its real weapons
 *   (AIC_fnc_vehicleWeapons: horns, smoke, flares, ... ignored):
 *     0 - unarmed (truck, car, transport helicopter without guns)
 *     1 - machine guns only (door gunners, a roof MG)
 *     2 - a cannon, rockets or missiles, or any tracked vehicle
 *   The one armament rule shared by AIC_fnc_findTransport (unarmed and
 *   lightly armed vehicles are taken for rides first), AIC_fnc_updateGroups
 *   (a group that only crews unarmed vehicles is transport-only) and
 *   AIC_fnc_supportCycle (machine-gun helicopters are transports, not CAS).
 *
 * Parameters:
 *   0: OBJECT - vehicle
 *
 * Returns:
 *   NUMBER - 0, 1 or 2 (0 for objNull)
 *
 * Example:
 *   if (([_veh] call AIC_fnc_vehicleArmament) < 2) then { ... };
 */

params [["_veh", objNull, [objNull]]];

if (isNull _veh) exitWith {0};

private _level = if (_veh isKindOf "Tank") then {2} else {0};
{
    private _sound = toLowerANSI getText (configFile >> "CfgWeapons" >> _x >> "nameSound");
    _level = _level max (if (_sound in ["cannon", "rockets", "missiles"]) then {2} else {1});
} forEach ([_veh, false] call AIC_fnc_vehicleWeapons);

_level
