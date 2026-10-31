/*
 * Name: AIC_fnc_isAntiAir
 * Description:
 *   Tells whether a ground vehicle is an anti-air vehicle: its editor
 *   subcategory is an anti-air one (modded vehicles usually follow the
 *   vanilla "EdSubcat_AAs" name), or one of its weapons fires ammunition
 *   made only for air targets (airLock 2). The answer is kept per class in
 *   AIC_ns key "antiAirClasses".
 *
 * Parameters:
 *   0: OBJECT - vehicle
 *
 * Returns:
 *   BOOL - true for an anti-air ground vehicle (false for objNull and aircraft)
 *
 * Example:
 *   if ([_veh] call AIC_fnc_isAntiAir) then { ... };
 */

params [["_veh", objNull, [objNull]]];

if (isNull _veh || {!(_veh isKindOf "LandVehicle")}) exitWith {false};

private _cache = AIC_ns getOrDefault ["antiAirClasses", createHashMap];
AIC_ns set ["antiAirClasses", _cache];
private _class = typeOf _veh;
if (_class in _cache) exitWith {_cache get _class};

private _result = ((toLowerANSI getText (configOf _veh >> "editorSubcategory")) find "_aa") >= 0;
if (!_result) then {
    {
        private _found = (getArray (configFile >> "CfgWeapons" >> _x >> "magazines")) findIf {
            private _ammo = getText (configFile >> "CfgMagazines" >> _x >> "ammo");
            getNumber (configFile >> "CfgAmmo" >> _ammo >> "airLock") >= 2
        };
        if (_found >= 0) exitWith {_result = true};
    } forEach ([_veh, false] call AIC_fnc_vehicleWeapons);
};

_cache set [_class, _result];
_result
