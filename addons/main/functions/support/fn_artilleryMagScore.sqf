/*
    Function: AIC_fnc_artilleryMagScore

    Description:
        Scores an artillery magazine for a fire mission of a kind: "HE"
        (default) HE-like magazines first, never smoke / illumination /
        flares / mines / laser-guided or guided rounds (score -1); "SMOKE"
        only smoke rounds; "ILLUM" only illumination rounds (flares). The
        one magazine rule shared by
        AIC_fnc_supportCycle (which batteries can fire at all) and
        AIC_fnc_fireMission (which magazine to fire), so a battery picked by
        the first is never refused by the second.

    Parameters:
        0: STRING - magazine class name
        1: STRING - (optional) kind: "HE" (default), "SMOKE", "ILLUM"

    Returns:
        NUMBER - score (higher = better), -1 if the magazine must not be used

    Example:
        private _usable = (getArtilleryAmmo [_gun]) select { ([_x] call AIC_fnc_artilleryMagScore) >= 0 };
*/

params [["_mag", "", [""]], ["_kind", "HE", [""]]];

if (_mag isEqualTo "") exitWith { -1 };

private _lower = toLowerANSI _mag;
private _tokens = _lower splitString "_";
if (_kind isEqualTo "SMOKE") exitWith {
    if ((_lower find "smoke") >= 0 && { (["mine", "guided", "laser"] findIf { (_lower find _x) >= 0 }) < 0 }) then { 1 } else { -1 }
};
if (_kind isEqualTo "ILLUM") exitWith {
    if (((_lower find "flare") >= 0 || { (_lower find "illum") >= 0 }) && { (["mine", "guided", "laser"] findIf { (_lower find _x) >= 0 }) < 0 }) then { 1 } else { -1 }
};
private _excluded = ["smoke", "flare", "illum", "mine", "laser", "guided", "_lg", "atmine", "apers", "demining"]
    findIf { (_lower find _x) >= 0 } >= 0;
if (_excluded || { "lg" in _tokens }) exitWith { -1 };

private _score = 1;
if ("he" in _tokens || { (_lower find "_he") >= 0 } || { (_lower find "he_") >= 0 }) then { _score = _score + 100; };
if ("shells" in _tokens || { "rockets" in _tokens }) then { _score = _score + 50; };
if ((_lower find "cluster") >= 0) then { _score = _score + 10; };

private _ammo = getText (configFile >> "CfgMagazines" >> _mag >> "ammo");
if (_ammo != "") then {
    _score = _score + ((getNumber (configFile >> "CfgAmmo" >> _ammo >> "indirectHit")) min 200) / 10;
};
_score
