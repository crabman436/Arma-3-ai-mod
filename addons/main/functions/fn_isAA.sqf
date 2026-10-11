/*
    CAI_fnc_isAA
    True if a unit or vehicle carries anti-air missiles (or is an AA vehicle).
    The answer is cached on the object.
    Params: 0: OBJECT
    Returns: BOOL
*/

params [["_obj", objNull, [objNull]]];

private _v = vehicle _obj;
if (isNull _v || {!alive _v}) exitWith {false};

// Cached: vehicles for good, soldiers for a minute (they can pick up a launcher).
private _cached = _v getVariable "CAI_isAA";
if (!isNil "_cached" && {(_cached select 1) > time}) exitWith {_cached select 0};

private _man = _v isKindOf "CAManBase";
private _mags = if (_man) then {
    // Includes the missile loaded in the launcher.
    (magazinesAmmoFull _v) apply {_x select 0}
} else {
    (magazinesAllTurrets _v) apply {_x select 0}
};
private _aa = ((toLower typeOf _v) find "_aa") >= 0 || {
    (_mags findIf {
        getNumber (configFile >> "CfgAmmo" >> getText (configFile >> "CfgMagazines" >> _x >> "ammo") >> "airLock") == 2
    }) >= 0
};

_v setVariable ["CAI_isAA", [_aa, [1e9, time + 60] select _man]];
_aa
