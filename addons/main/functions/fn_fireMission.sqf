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
        4: NUMBER rounds (default CAI_artilleryRounds)
        5: STRING "HE", "SMOKE" or "ILLUM"
        6: NUMBER seconds before the gun takes another mission (default CAI_artilleryCooldown)
    Returns: BOOL - a fire mission was sent
*/

params ["_side", "_targetPos", ["_error", 30], ["_caller", "HQ"], ["_rounds", -1], ["_kind", "HE"], ["_cooldown", -1]];

if (_rounds < 1) then {_rounds = CAI_artilleryRounds};
if (_cooldown < 0) then {_cooldown = CAI_artilleryCooldown};
_targetPos = [_targetPos select 0, _targetPos select 1, 0];

// Danger close check (illumination bursts high up and is always safe).
private _safeDist = switch (_kind) do {
    case "HE": {CAI_artillerySafeDistance};
    case "SMOKE": {60};
    default {0};
};
if (_safeDist > 0) then {
    private _blocked = (_targetPos nearEntities [["CAManBase", "LandVehicle"], _safeDist]) findIf {
        alive _x && {((side _x) getFriend _side) >= 0.6}
    };
    if (_blocked >= 0) then {_targetPos = []};
};
if (_targetPos isEqualTo []) exitWith {false};

// Don't stack fire missions of the same kind on the same spot.
if (isNil "CAI_fireMissions") then {CAI_fireMissions = []};
CAI_fireMissions = CAI_fireMissions select {time - (_x select 1) < (_x select 3)};
if ((CAI_fireMissions findIf {(_x select 2) == _kind && {(_x select 0) distance2D _targetPos < 150}}) >= 0) exitWith {false};

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
    private _mag = _mags param [_mags findIf {
        private _m = toLower _x;
        switch (_kind) do {
            case "SMOKE": {(_m find "smoke") >= 0};
            case "ILLUM": {(_m find "flare") >= 0 || {(_m find "illum") >= 0}};
            // Plain HE: skip smoke, illumination, mines, cluster and guided rounds.
            default {(["smoke", "flare", "illum", "mine", "cluster", "guided", "_lg", "laser"] findIf {(_m find _x) >= 0}) < 0};
        }
    }, ""];
    if (_mag != "" && {_targetPos inRangeOfArtillery [[_gun], _mag]}) exitWith {
        private _aim = _targetPos getPos [random (_error + 20), random 360];
        _gun doArtilleryFire [_aim, _mag, _rounds];
        _gun setVariable ["CAI_nextFire", time + _cooldown];
        CAI_fireMissions pushBack [_targetPos, time, _kind, [_cooldown, 120] select (_kind == "ILLUM")];
        _fired = true;
        format ["Fire mission: %1 firing %2 %3 rounds for %4", getText (configOf _gun >> "displayName"), _rounds, _kind, _caller] call CAI_fnc_log;
    };
} forEach _guns;

_fired
