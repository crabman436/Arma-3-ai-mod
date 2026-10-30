/*
 * Name: AIC_fnc_groupPower
 * Description:
 *   Rough combat value of a group (used for own groups and for enemy
 *   contacts). Units on foot, in cargo or in FFV person turrets count as
 *   infantry (1 each, scaled by their health). Every vehicle crewed by the
 *   group adds a value by vehicle type:
 *
 *     type    armed   unarmed
 *     MOTOR     3       1      (light vehicle)
 *     MECH      6       3      (APC / IFV)
 *     ARMOR    10       3      (tank)
 *     HELI     10       2      (attack / transport helicopter)
 *     PLANE    12       2
 *     ARTY      4       1
 *     STATIC    2       0.5
 *     NAVAL     4       1
 *
 *   "Armed" means the vehicle has a real weapon (horns, smoke launchers,
 *   flares, searchlights, designators and fake weapons ignored - see
 *   AIC_fnc_vehicleWeapons) on a turret that is occupied by an
 *   alive unit and the vehicle can still fire. Vehicle value is scaled by
 *   (1 - damage); immobilised mobile vehicles are scaled by 0.6.
 *
 * Parameters:
 *   0: GROUP - group to evaluate
 *
 * Returns:
 *   NUMBER - combat power (0 for null / dead groups)
 *
 * Example:
 *   private _power = [_grp] call AIC_fnc_groupPower;
 */

params [["_group", grpNull, [grpNull]]];

if (isNull _group) exitWith {0};

private _units = (units _group) select {alive _x};
if (_units isEqualTo []) exitWith {0};

private _armedValue = createHashMapFromArray [
    ["MOTOR", 3], ["MECH", 6], ["ARMOR", 10], ["HELI", 10],
    ["PLANE", 12], ["ARTY", 4], ["STATIC", 2], ["NAVAL", 4]
];
private _unarmedValue = createHashMapFromArray [
    ["MOTOR", 1], ["MECH", 3], ["ARMOR", 3], ["HELI", 2],
    ["PLANE", 2], ["ARTY", 1], ["STATIC", 0.5], ["NAVAL", 1]
];

private _power = 0;
private _vehicles = [];

{
    private _unit = _x;
    private _veh = objectParent _unit;
    if (isNull _veh) then {
        _power = _power + (1 - (damage _unit));
    } else {
        _vehicles pushBackUnique _veh;
    };
} forEach _units;

{
    private _veh = _x;
    private _crewList = fullCrew [_veh, "", false];

    // Split this group's members in the vehicle into crew and passengers
    private _ourCrew = [];
    private _passengers = 0;
    {
        _x params ["_crewUnit", "_role", "", "", ["_isPersonTurret", false]];
        if (alive _crewUnit && {group _crewUnit isEqualTo _group}) then {
            if (_role == "cargo" || {_isPersonTurret}) then {
                _passengers = _passengers + (1 - (damage _crewUnit));
            } else {
                _ourCrew pushBack _crewUnit;
            };
        };
    } forEach _crewList;

    _power = _power + _passengers;

    if (_ourCrew isNotEqualTo []) then {
        private _vType = [_veh] call AIC_fnc_vehicleType;

        // Weapons on turrets that are actually manned (driver = [-1])
        private _armed = ([_veh, true] call AIC_fnc_vehicleWeapons) isNotEqualTo [];

        if (_armed && {!canFire _veh}) then {_armed = false};

        private _value = if (_armed) then {
            _armedValue getOrDefault [_vType, 1]
        } else {
            _unarmedValue getOrDefault [_vType, 0.5]
        };

        _value = _value * (1 - (damage _veh));

        if (!(_vType in ["STATIC", "ARTY"]) && {!canMove _veh}) then {
            // Self-propelled artillery that cannot move still fires, but mobile units lose a lot
            _value = _value * 0.6;
        };
        if (_vType == "ARTY" && {!(_veh isKindOf "StaticWeapon")} && {!canMove _veh}) then {
            _value = _value * 0.9;
        };

        _power = _power + (_value max 0);
    };
} forEach _vehicles;

_power max 0
