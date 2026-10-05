/*
    CAI_fnc_threatValue
    Rough combat power of a unit or vehicle, used to decide when a group is outmatched.
    Params: 0: OBJECT
    Returns: NUMBER
*/

params [["_obj", objNull, [objNull]]];

private _v = vehicle _obj;
if (isNull _v || {!alive _v}) exitWith {0};
if (_v isKindOf "CAManBase") exitWith {1};
if (_v isKindOf "Tank") exitWith {8};
if (_v isKindOf "Wheeled_APC_F") exitWith {5};
if (_v isKindOf "Plane") exitWith {8};
if (_v isKindOf "Helicopter") exitWith {[2, 6] select (count (_v weaponsTurret [-1] + _v weaponsTurret [0]) > 1)};
if (_v isKindOf "StaticWeapon") exitWith {2};
if (_v isKindOf "Car") exitWith {[1, 3] select (count (_v weaponsTurret [0]) > 0)};
2
