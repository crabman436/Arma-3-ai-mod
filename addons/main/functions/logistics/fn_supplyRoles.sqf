/*
 * Name: AIC_fnc_supplyRoles
 * Description:
 *   What a vehicle can supply, from its config: "repair", "fuel", "ammo".
 *   Supply trucks are kept out of troop transport (AIC_fnc_findTransport).
 *   The roles come from the class, so they are read once per vehicle class
 *   and cached in AIC_ns "supplyRolesClasses" (like AIC_fnc_vehicleArmament).
 *
 * Parameters:
 *   0: OBJECT - vehicle
 *
 * Returns:
 *   ARRAY - any of "repair", "fuel", "ammo"; [] for an ordinary vehicle
 *           (a copy, callers may change it)
 *
 * Example:
 *   if ("ammo" in ([_truck] call AIC_fnc_supplyRoles)) then { ... };
 */

params [["_veh", objNull, [objNull]]];

if (isNull _veh) exitWith {[]};

// the roles come from the class: looked up once per class (AIC_ns "supplyRolesClasses")
if (isNil "AIC_ns") then {call AIC_fnc_preInit};
private _cache = AIC_ns getOrDefault ["supplyRolesClasses", createHashMap];
AIC_ns set ["supplyRolesClasses", _cache];
private _class = typeOf _veh;
if (_class in _cache) exitWith {+(_cache get _class)};

private _cfg = configOf _veh;
private _roles = [];
if (getNumber (_cfg >> "transportRepair") > 0) then {_roles pushBack "repair"};
if (getNumber (_cfg >> "transportFuel") > 0) then {_roles pushBack "fuel"};
if (getNumber (_cfg >> "transportAmmo") > 0) then {_roles pushBack "ammo"};

_cache set [_class, _roles];
+_roles
