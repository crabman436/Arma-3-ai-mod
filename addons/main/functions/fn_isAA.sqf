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

private _cached = _v getVariable "CAI_isAA";
if (!isNil "_cached") exitWith {_cached};

private _mags = if (_v isKindOf "CAManBase") then {
    magazines _v
} else {
    (magazinesAllTurrets _v) apply {_x select 0}
};
private _aa = ((toLower typeOf _v) find "_aa") >= 0 || {
    (_mags findIf {
        getNumber (configFile >> "CfgAmmo" >> getText (configFile >> "CfgMagazines" >> _x >> "ammo") >> "airLock") == 2
    }) >= 0
};

_v setVariable ["CAI_isAA", _aa];
_aa
