/*
 * Name: AIC_fnc_vehicleType
 * Description:
 *   Group type a crewed vehicle stands for. The one decision tree shared by
 *   AIC_fnc_classifyGroup and AIC_fnc_groupPower, so classification and
 *   power estimate can never disagree:
 *     Plane                                  -> PLANE
 *     Helicopter / other Air                 -> HELI
 *     Ship                                   -> NAVAL
 *     artilleryScanner = 1                   -> ARTY
 *     StaticWeapon                           -> STATIC
 *     Wheeled_APC_F / Tracked_APC            -> MECH
 *     Tank (APC subcategory or >= 6 seats)   -> MECH
 *     Tank                                   -> ARMOR
 *     anything else                          -> MOTOR
 *
 * Parameters:
 *   0: OBJECT - vehicle
 *
 * Returns:
 *   STRING - "PLANE", "HELI", "NAVAL", "ARTY", "STATIC", "MECH", "ARMOR" or
 *            "MOTOR" ("MOTOR" for objNull)
 *
 * Example:
 *   private _vType = [objectParent player] call AIC_fnc_vehicleType;
 */

params [["_veh", objNull, [objNull]]];

if (isNull _veh) exitWith {"MOTOR"};

private _cfg = configOf _veh;
if (_veh isKindOf "Plane") exitWith {"PLANE"};
if (_veh isKindOf "Helicopter" || {_veh isKindOf "Air"}) exitWith {"HELI"};
if (_veh isKindOf "Ship") exitWith {"NAVAL"};
if (getNumber (_cfg >> "artilleryScanner") == 1) exitWith {"ARTY"};
if (_veh isKindOf "StaticWeapon") exitWith {"STATIC"};
if (_veh isKindOf "Wheeled_APC_F" || {_veh isKindOf "Tracked_APC"}) exitWith {"MECH"};
if (_veh isKindOf "Tank") exitWith {
    if (
        getText (_cfg >> "editorSubcategory") == "EdSubcat_APCs"
        || {getNumber (_cfg >> "transportSoldier") >= 6}
    ) then {"MECH"} else {"ARMOR"}
};
"MOTOR"
