/*
 * Name: AIC_fnc_suppressWatch
 * Description:
 *   Keeps a group's suppressive fire going (spawned once per group by
 *   AIC_fnc_suppressFor, flag "AIC_suppressWatch"). A doSuppressiveFire is
 *   a burst, not a standing order, and the commander cycle is too slow to
 *   repeat it, so this watcher re-issues the jobs in the group variable
 *   "AIC_suppress" = [[[unit, positionASL], ...], untilTime] every
 *   AIC_SUPPRESS_PERIOD s (through AIC_fnc_do: the units may run on a
 *   headless client). It ends when the time is up, the variable is cleared
 *   (a new order, AIC_fnc_clearWaypoints), or the group is gone; on its way
 *   out it clears the variable and the flag.
 *
 *   Vehicles (measured on the dedicated server): a vehicle given
 *   doSuppressiveFire has its gunner on "Suppress" at once but fires
 *   nothing for about 75 s of repeated orders, then fires freely; a single
 *   order is dropped after 10 s. So besides the order the watcher works the
 *   turret itself until the AI takes over: the gunner and the vehicle watch
 *   the point, and once the barrel is within AIC_SUPPRESS_AIM degrees of it
 *   (up to 4 s) the gunner fires a burst with forceWeaponFire,
 *   AIC_SUPPRESS_VEH_SHOTS_MG rounds from a machine gun of the turret if it
 *   has one (selected with selectWeaponTurret), else
 *   AIC_SUPPRESS_VEH_SHOTS rounds of the current weapon. Nothing is fired
 *   with the barrel off the point or the weapon empty.
 *
 * Parameters:
 *   0: GROUP - the group on overwatch
 *
 * Returns:
 *   Nothing (spawned)
 *
 * Example:
 *   [_group] spawn AIC_fnc_suppressWatch;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_group", grpNull, [grpNull]]];

if (isNull _group) exitWith {};

// a machine gun of the turret, else "" (the current weapon stays)
private _fnc_mgOf = {
    params ["_v", "_turret"];
    private _mg = "";
    {
        private _w = toLowerANSI _x;
        if ((["mg", "gatling", "minigun"] findIf { (_w find _x) >= 0 }) >= 0 && { !((_w find "smoke") >= 0) }) exitWith { _mg = _x; };
    } forEach (_v weaponsTurret _turret);
    _mg
};

// the turret on the point, then a burst
private _fnc_vehicleBurst = {
    params ["_v", "_p"];
    private _g = gunner _v;
    if (isNull _g || { !alive _g } || { isPlayer _g }) exitWith {};
    private _role = assignedVehicleRole _g;
    if (!(_role isEqualType []) || { count _role < 2 } || { !((_role select 1) isEqualType []) }) exitWith {};
    private _turret = _role select 1;
    private _mg = [_v, _turret] call _fnc_mgOf;
    private _ws = weaponState [_v, _turret];
    if (!(_ws isEqualType []) || { count _ws < 3 }) exitWith {};
    if (_mg isNotEqualTo "" && { (_ws select 0) isNotEqualTo _mg } && { (_v ammo _mg) > 0 }) then {
        [_v, "selectWeaponTurret", [_mg, _turret]] call AIC_fnc_do;
        sleep 0.5;
        _ws = weaponState [_v, _turret];
        if (!(_ws isEqualType []) || { count _ws < 3 }) exitWith {};
    };
    _ws params ["_wpn", "_muzzle", "_mode"];
    if (_wpn isEqualTo "" || { _muzzle isEqualTo "" } || { _mode isEqualTo "" } || { (_v ammo _wpn) <= 0 }) exitWith {};
    private _aim = ASLToAGL _p;
    [_g, "doWatch", _aim] call AIC_fnc_do;
    [_v, "doWatch", _aim] call AIC_fnc_do;
    private _t0 = time;
    private _onTarget = false;
    waitUntil {
        sleep 0.5;
        if (isNull _v || { !alive _v } || { isNull _g } || { !alive _g }) exitWith { true };
        private _dir = _v weaponDirection _wpn;
        private _want = vectorNormalized (_p vectorDiff (getPosASL _v));
        _onTarget = (acos (((_dir vectorCos _want) max -1) min 1)) < AIC_SUPPRESS_AIM;
        _onTarget || { (time - _t0) > 4 }
    };
    if (!_onTarget || { isNull _v } || { !alive _v }) exitWith {};
    private _shots = [AIC_SUPPRESS_VEH_SHOTS, AIC_SUPPRESS_VEH_SHOTS_MG] select (_wpn isEqualTo _mg);
    for "_i" from 1 to _shots do {
        if (isNull _g || { !alive _g } || { !alive _v } || { (_v ammo _wpn) <= 0 }) exitWith {};
        [_g, "forceWeaponFire", [_muzzle, _mode]] call AIC_fnc_do;
        sleep 0.3;
    };
};

while {
    !isNull _group && {alive leader _group} && {
        private _job = _group getVariable ["AIC_suppress", []];
        _job isEqualType [] && {count _job >= 2} && {time <= (_job select 1)}
    }
} do {
    private _job = _group getVariable ["AIC_suppress", []];
    private _t0 = time;
    {
        _x params ["_u", "_p"];
        // a man of the group, or a vehicle still crewed by the group
        private _ours = if (_u isKindOf "CAManBase") then {
            !isPlayer _u && {(group _u) isEqualTo _group}
        } else {
            ((crew _u) findIf {alive _x && {(group _x) isEqualTo _group}}) >= 0 && {((crew _u) findIf {isPlayer _x}) < 0}
        };
        if (!isNull _u && {alive _u} && {_ours}) then {
            [_u, "doSuppressiveFire", _p] call AIC_fnc_do;
            if !(_u isKindOf "CAManBase") then { [_u, _p] call _fnc_vehicleBurst; };
        };
    } forEach (_job select 0);
    sleep ((AIC_SUPPRESS_PERIOD - (time - _t0)) max 1);
};

if (!isNull _group) then {
    _group setVariable ["AIC_suppress", nil];
    _group setVariable ["AIC_suppressWatch", nil];
};
