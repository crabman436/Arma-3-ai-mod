/*
    CAI_fnc_fireMission
    Sends one fire mission from an idle friendly mortar or artillery piece.
    Never fires when friendlies (or civilians) are within the safe distance of
    the target, and doesn't stack missions on the same spot.

    Params:
        0: SIDE requesting side
        1: ARRAY target position
        2: NUMBER location error in meters (scatter)
        3: STRING who asked (for debug messages)
    Returns: BOOL - a fire mission was sent
*/

params ["_side", "_targetPos", ["_error", 30], ["_caller", "HQ"]];

_targetPos = [_targetPos select 0, _targetPos select 1, 0];

// Danger close check.
private _blocked = (_targetPos nearEntities [["CAManBase", "LandVehicle"], CAI_artillerySafeDistance]) findIf {
    alive _x && {((side _x) getFriend _side) >= 0.6}
};
if (_blocked >= 0) exitWith {false};

// Don't stack fire missions on the same spot.
if (isNil "CAI_fireMissions") then {CAI_fireMissions = []};
CAI_fireMissions = CAI_fireMissions select {time - (_x select 1) < CAI_artilleryCooldown};
if ((CAI_fireMissions findIf {(_x select 0) distance2D _targetPos < 150}) >= 0) exitWith {false};

private _guns = vehicles select {
    alive _x
    && {local _x}
    && {getNumber (configOf _x >> "artilleryScanner") == 1}
    && {alive gunner _x}
    && {!isPlayer gunner _x}
    && {((side _x) getFriend _side) >= 0.6}
    && {time >= (_x getVariable ["CAI_nextFire", 0])}
    && {!((group gunner _x) getVariable ["CAI_exclude", false])}
};

private _fired = false;
{
    private _gun = _x;
    private _mags = getArtilleryAmmo [_gun];
    // Plain HE: skip smoke, illumination, mines, cluster and guided rounds.
    private _mag = _mags param [_mags findIf {
        private _m = toLower _x;
        (["smoke", "flare", "illum", "mine", "cluster", "guided", "_lg", "laser"] findIf {(_m find _x) >= 0}) < 0
    }, ""];
    if (_mag != "" && {_targetPos inRangeOfArtillery [[_gun], _mag]}) exitWith {
        private _aim = _targetPos getPos [random (_error + 20), random 360];
        _gun doArtilleryFire [_aim, _mag, CAI_artilleryRounds];
        _gun setVariable ["CAI_nextFire", time + CAI_artilleryCooldown];
        CAI_fireMissions pushBack [_targetPos, time];
        _fired = true;
        format ["Fire mission: %1 firing %2 rounds for %3", getText (configOf _gun >> "displayName"), CAI_artilleryRounds, _caller] call CAI_fnc_log;
    };
} forEach _guns;

_fired
