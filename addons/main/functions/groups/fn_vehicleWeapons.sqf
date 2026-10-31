/*
 * Name: AIC_fnc_vehicleWeapons
 * Description:
 *   The real weapons of a vehicle: every weapon on the driver / pilot
 *   turret [-1] and the other (non-FFV) turrets, without horns, smoke
 *   launchers, countermeasure flares, searchlights, laser designators and
 *   fake weapons. The one ignore list used by every subsystem that asks
 *   "is this vehicle armed?" (AIC_fnc_groupPower, AIC_fnc_findTransport,
 *   AIC_fnc_supportCycle), so they always agree. The weapon lists are read
 *   once per vehicle class (a scripted weapon change on one vehicle is not
 *   seen); which turrets are manned is always live.
 *
 * Parameters:
 *   0: OBJECT - vehicle
 *   1: BOOL   - (optional) only turrets manned by an alive unit, default false
 *
 * Returns:
 *   ARRAY - weapon class names (may contain duplicates; [] = unarmed)
 *
 * Example:
 *   private _armed = ([_veh, true] call AIC_fnc_vehicleWeapons) isNotEqualTo [];
 */

params [
    ["_veh", objNull, [objNull]],
    ["_mannedOnly", false, [false]]
];

if (isNull _veh) exitWith {[]};

// the turrets and their weapons come from the class: enumerated once per
// class (AIC_ns "turretWeaponsClasses"), only the manning is live
if (isNil "AIC_ns") then {call AIC_fnc_preInit};
private _cache = AIC_ns getOrDefault ["turretWeaponsClasses", createHashMap];
AIC_ns set ["turretWeaponsClasses", _cache];
private _class = typeOf _veh;
if !(_class in _cache) then {
    private _ignored = ["horn", "smoke", "flare", "searchlight", "laserdesignator", "fakeweapon", "fake_weapon"];
    private _turrets = [];
    {
        private _real = (_veh weaponsTurret _x) select {
            private _w = toLowerANSI _x;
            (_ignored findIf {(_w find _x) >= 0}) < 0
        };
        if (_real isNotEqualTo []) then {_turrets pushBack [_x, _real]};
    } forEach ([[-1]] + (allTurrets [_veh, false]));
    _cache set [_class, _turrets];
};
private _turrets = _cache get _class;

if (!_mannedOnly) exitWith {
    private _all = [];
    {_all append (_x select 1)} forEach _turrets;
    _all
};

private _weapons = [];
{
    _x params ["_path", "_real"];
    private _operator = if (_path isEqualTo [-1]) then {driver _veh} else {_veh turretUnit _path};
    if (!isNull _operator && {alive _operator}) then {_weapons append _real};
} forEach _turrets;

_weapons
