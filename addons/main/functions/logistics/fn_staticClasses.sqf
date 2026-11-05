/*
    Function: AIC_fnc_staticClasses

    Description:
        The static weapons a commander's side can set up, by role, from the
        loaded config (server). The faction is the one most of the
        commander's group leaders belong to, so a modded army gets its own
        guns. Every public (scope 2) "StaticWeapon" of that faction is
        sorted by its class name and config:
          "AA"  - name or editorSubcategory with "_aa"
          "AT"  - name with "_at_", "static_at" or "_atgm" (launcher on a tripod)
          "GMG" - name with "gmg"
          "HMG" - any other gun (high tripods preferred: they fire over
                  sandbags), never a mortar or other artillery
                  (artilleryScanner 1) or a weapon without magazines.
        A role the faction has nothing for falls back to the vanilla gun of
        the side (B_ / O_ / I_ HMG_01_high, GMG_01_high, static_AT,
        static_AA), if that class exists. Cached per faction in AIC_ns
        "staticClasses".

    Parameters:
        0: HASHMAP - commander

    Returns:
        HASHMAP - role -> array of class names (a role may be empty)

    Example:
        private _hmg = selectRandom (([_cmd] call AIC_fnc_staticClasses) get "HMG");
*/

params [["_cmd", createHashMap, [createHashMap]]];

private _side = _cmd getOrDefault ["side", sideUnknown];
private _empty = createHashMapFromArray [["HMG", []], ["GMG", []], ["AT", []], ["AA", []]];
if (isNil "AIC_ns") exitWith { _empty };

// the faction most leaders belong to
private _count = createHashMap;
{
    private _f = faction (leader _x);
    if (_f isNotEqualTo "") then { _count set [_f, (_count getOrDefault [_f, 0]) + 1]; };
} forEach ((_cmd getOrDefault ["groups", []]) select { !isNull _x && { alive leader _x } });
private _faction = "";
private _best = 0;
{ if (_y > _best) then { _best = _y; _faction = _x; }; } forEach _count;

private _cache = AIC_ns getOrDefault ["staticClasses", createHashMap];
AIC_ns set ["staticClasses", _cache];
private _key = format ["%1|%2", _side, _faction];
if (_key in _cache) exitWith { _cache get _key };

private _roles = createHashMapFromArray [["HMG", []], ["GMG", []], ["AT", []], ["AA", []]];
if (_faction isNotEqualTo "") then {
    private _cfgs = format ["getNumber (_x >> 'scope') == 2 && { getText (_x >> 'faction') == '%1' } && { (configName _x) isKindOf 'StaticWeapon' }", _faction]
        configClasses (configFile >> "CfgVehicles");
    {
        private _cls = configName _x;
        private _n = toLowerANSI _cls;
        private _sub = toLowerANSI getText (_x >> "editorSubcategory");
        if (getNumber (_x >> "artilleryScanner") == 1) then { continue };
        // some magazine on some turret: a real weapon
        private _mags = [];
        { _mags append getArray (_x >> "magazines"); } forEach ("true" configClasses (_x >> "Turrets"));
        if (_mags isEqualTo []) then { continue };
        private _role = switch (true) do {
            case ((_n find "_aa") >= 0 || { (_sub find "_aa") >= 0 }): { "AA" };
            case ((_n find "_at_") >= 0 || { (_n find "static_at") >= 0 } || { (_n find "_atgm") >= 0 }): { "AT" };
            case ((_n find "gmg") >= 0): { "GMG" };
            default { "HMG" };
        };
        (_roles get _role) pushBack _cls;
    } forEach _cfgs;
    // high tripods first: they fire over a sandbag wall
    {
        private _l = _roles get _x;
        _roles set [_x, (_l select { (toLowerANSI _x find "high") >= 0 }) + (_l select { (toLowerANSI _x find "high") < 0 })];
    } forEach ["HMG", "GMG"];
};

// vanilla fallback of the side
private _p = ["B", "O", "I", "C"] param [[west, east, independent, civilian] find _side, ""];
if (_p isNotEqualTo "C" && { _p isNotEqualTo "" }) then {
    {
        _x params ["_role", "_cls"];
        if ((_roles get _role) isEqualTo [] && { isClass (configFile >> "CfgVehicles" >> _cls) }) then {
            (_roles get _role) pushBack _cls;
        };
    } forEach [
        ["HMG", _p + "_HMG_01_high_F"], ["GMG", _p + "_GMG_01_high_F"],
        ["AT", _p + "_static_AT_F"], ["AA", _p + "_static_AA_F"]
    ];
};

_cache set [_key, _roles];
["staticClasses: %1 (%2) HMG %3, GMG %4, AT %5, AA %6", [_side, _faction,
    count (_roles get "HMG"), count (_roles get "GMG"), count (_roles get "AT"), count (_roles get "AA")]] call AIC_fnc_log;
_roles
