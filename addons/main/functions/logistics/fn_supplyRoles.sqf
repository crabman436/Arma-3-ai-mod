/*
 * Name: AIC_fnc_supplyRoles
 * Description:
 *   What a vehicle can supply, from its config: "repair", "fuel", "ammo".
 *   Supply trucks are kept out of troop transport (AIC_fnc_findTransport).
 *
 * Parameters:
 *   0: OBJECT - vehicle
 *
 * Returns:
 *   ARRAY - any of "repair", "fuel", "ammo"; [] for an ordinary vehicle
 *
 * Example:
 *   if ("ammo" in ([_truck] call AIC_fnc_supplyRoles)) then { ... };
 */

params [["_veh", objNull, [objNull]]];

if (isNull _veh) exitWith {[]};

private _cfg = configOf _veh;
private _roles = [];
if (getNumber (_cfg >> "transportRepair") > 0) then {_roles pushBack "repair"};
if (getNumber (_cfg >> "transportFuel") > 0) then {_roles pushBack "fuel"};
if (getNumber (_cfg >> "transportAmmo") > 0) then {_roles pushBack "ammo"};

_roles
