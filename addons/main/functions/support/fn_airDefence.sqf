/*
    Function: AIC_fnc_airDefence

    Description:
        How dangerous a group is to aircraft:
          0 - nothing that can hit them
          1 - a shoulder-fired anti-air launcher (a unit carrying a launcher
              whose ammunition is made only for air targets, airLock 2)
          2 - an anti-air vehicle it crews (AIC_fnc_isAntiAir)
        Launcher classes are judged once (AIC_ns "aaLauncherClasses").

    Parameters:
        0: GROUP - group (usually an enemy contact's)

    Returns:
        NUMBER - 0, 1 or 2

    Example:
        if (([_contact get "group"] call AIC_fnc_airDefence) >= 2) then { ... };
*/

params [["_group", grpNull, [grpNull]]];

if (isNull _group) exitWith { 0 };
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _cache = AIC_ns getOrDefault ["aaLauncherClasses", createHashMap];
AIC_ns set ["aaLauncherClasses", _cache];

private _level = 0;
{
    if (!alive _x) then { continue };
    private _veh = objectParent _x;
    if (!isNull _veh && { [_veh] call AIC_fnc_isAntiAir }) exitWith { _level = 2; };

    private _launcher = secondaryWeapon _x;
    if (_launcher isEqualTo "") then { continue };
    if !(_launcher in _cache) then {
        _cache set [_launcher, (getArray (configFile >> "CfgWeapons" >> _launcher >> "magazines")) findIf {
            private _ammo = getText (configFile >> "CfgMagazines" >> _x >> "ammo");
            getNumber (configFile >> "CfgAmmo" >> _ammo >> "airLock") >= 2
        } >= 0];
    };
    if (_cache get _launcher) then { _level = _level max 1; };
} forEach (units _group);

_level
