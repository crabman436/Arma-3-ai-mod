/*
 * Name: AIC_fnc_vehicleWeapons
 * Description:
 *   The real weapons of a vehicle: every weapon on the driver / pilot
 *   turret [-1] and the other (non-FFV) turrets, without horns, smoke
 *   launchers, countermeasure flares, searchlights, laser designators and
 *   fake weapons. The one ignore list used by every subsystem that asks
 *   "is this vehicle armed?" (AIC_fnc_groupPower, AIC_fnc_findTransport,
 *   AIC_fnc_supportCycle), so they always agree.
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

private _ignored = ["horn", "smoke", "flare", "searchlight", "laserdesignator", "fakeweapon", "fake_weapon"];

private _weapons = [];
{
    private _path = _x;
    private _manned = !_mannedOnly || {
        private _operator = if (_path isEqualTo [-1]) then {driver _veh} else {_veh turretUnit _path};
        !isNull _operator && {alive _operator}
    };
    if (_manned) then {
        _weapons append ((_veh weaponsTurret _path) select {
            private _w = toLowerANSI _x;
            (_ignored findIf {(_w find _x) >= 0}) < 0
        });
    };
} forEach ([[-1]] + (allTurrets [_veh, false]));

_weapons
