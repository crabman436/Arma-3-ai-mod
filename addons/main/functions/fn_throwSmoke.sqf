/*
    CAI_fnc_throwSmoke
    The first soldier in the list carrying a smoke grenade throws it toward
    the enemy.
    Params: 0: ARRAY units, 1: ARRAY enemy position
    Returns: BOOL - a smoke was thrown
*/

params ["_units", "_towardPos"];

private _throwCfg = configFile >> "CfgWeapons" >> "Throw";
private _getMuzzle = {
    params ["_unit"];
    private _mags = magazines _unit;
    private _muzzle = "";
    {
        if ((toLower _x) find "smoke" >= 0
            && {(getArray (_throwCfg >> _x >> "magazines") findIf {_x in _mags}) >= 0}
        ) exitWith {_muzzle = _x};
    } forEach getArray (_throwCfg >> "muzzles");
    _muzzle
};

private _thrower = objNull;
private _muzzle = "";
{
    if (alive _x && {vehicle _x == _x} && {!isPlayer _x}) then {
        private _m = [_x] call _getMuzzle;
        if (_m != "" && {isNull _thrower}) then {
            _thrower = _x;
            _muzzle = _m;
        };
    };
} forEach _units;

if (isNull _thrower) exitWith {false};

[_thrower, _muzzle, _towardPos] spawn {
    params ["_unit", "_muzzle", "_pos"];
    _unit doWatch _pos;
    sleep 1.5;
    if (alive _unit) then {
        _unit forceWeaponFire [_muzzle, _muzzle];
    };
    sleep 2;
    _unit doWatch objNull;
};

true
