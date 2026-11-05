/*
    Function: AIC_fnc_onRunway

    Description:
        Whether a position is on (or too close to) a runway or taxiway of the
        map's airfields, so nothing is built or parked where planes roll.
        From the world config, read once per mission (AIC_ns "runways"):
        every airport ("ilsPosition" of the world and of each
        "SecondaryAirports" entry) gives a line AIC_FORT_RUNWAY_LEN m both
        ways along its "ilsDirection" (the approach line is kept clear too),
        and its "ilsTaxiIn" / "ilsTaxiOff" paths. A position closer than
        the given clearance (default AIC_FORT_RUNWAY_CLEAR m, 2D) to any of
        these segments counts.

    Parameters:
        0: ARRAY  - position
        1: NUMBER - (optional) clearance in m, default AIC_FORT_RUNWAY_CLEAR

    Returns:
        BOOL

    Example:
        if !([_pos] call AIC_fnc_onRunway) then { ... };
*/

#include "\z\aic\addons\main\script_component.hpp"

params [["_pos", [], [[]]], ["_clear", AIC_FORT_RUNWAY_CLEAR, [0]]];
if (count _pos < 2 || { isNil "AIC_ns" }) exitWith { false };

private _segs = AIC_ns getOrDefault ["runways", -1];
if (_segs isEqualTo -1) then {
    _segs = [];
    private _fnc_airport = {
        params ["_cfg"];
        private _p = getArray (_cfg >> "ilsPosition");
        private _d = getArray (_cfg >> "ilsDirection");
        if (count _p >= 2 && { count _d >= 3 } && { (_p select 0) != 0 || { (_p select 1) != 0 } }) then {
            private _v = vectorNormalized [_d select 0, _d select 2, 0];
            private _a = [_p select 0, _p select 1, 0];
            _segs pushBack [_a vectorAdd (_v vectorMultiply AIC_FORT_RUNWAY_LEN), _a vectorAdd (_v vectorMultiply -AIC_FORT_RUNWAY_LEN)];
        };
        {
            private _t = getArray (_cfg >> _x);
            for "_i" from 0 to ((count _t) - 4) step 2 do {
                _segs pushBack [[_t select _i, _t select (_i + 1), 0], [_t select (_i + 2), _t select (_i + 3), 0]];
            };
        } forEach ["ilsTaxiIn", "ilsTaxiOff"];
    };
    private _world = configFile >> "CfgWorlds" >> worldName;
    [_world] call _fnc_airport;
    private _sec = _world >> "SecondaryAirports";
    if (isClass _sec) then {
        for "_i" from 0 to ((count _sec) - 1) do {
            if (isClass (_sec select _i)) then { [_sec select _i] call _fnc_airport; };
        };
    };
    AIC_ns set ["runways", _segs];
};
if (_segs isEqualTo []) exitWith { false };

private _p = [_pos select 0, _pos select 1, 0];
(_segs findIf {
    _x params ["_a", "_b"];
    private _ab = _b vectorDiff _a;
    private _len2 = _ab vectorDotProduct _ab;
    private _t = if (_len2 <= 0) then { 0 } else { ((((_p vectorDiff _a) vectorDotProduct _ab) / _len2) max 0) min 1 };
    (_p distance2D (_a vectorAdd (_ab vectorMultiply _t))) < _clear
}) >= 0
