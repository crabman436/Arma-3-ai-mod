/*
    Function: AIC_fnc_airfields

    Description:
        The map's airfields, from the world config: the main airport (id 0,
        "ilsPosition") and the "SecondaryAirports" (ids 1, 2, ... in config
        order), the ids AI planes land at (landAt). Read once per mission
        (AIC_ns "airfields").

    Parameters:
        None

    Returns:
        ARRAY - [[id, [x, y, 0]], ...], [] on a map without airfields

    Example:
        { systemChat str _x; } forEach (call AIC_fnc_airfields);
*/

if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _cached = AIC_ns getOrDefault ["airfields", []];
if (_cached isNotEqualTo [] || { AIC_ns getOrDefault ["airfieldsRead", false] }) exitWith { _cached };

private _world = configFile >> "CfgWorlds" >> worldName;
private _fields = [];
private _main = getArray (_world >> "ilsPosition");
if (count _main >= 2 && { (_main select 0) != 0 || { (_main select 1) != 0 } }) then {
    _fields pushBack [0, [_main select 0, _main select 1, 0]];
};
private _secondary = _world >> "SecondaryAirports";
if (isClass _secondary) then {
    for "_i" from 0 to ((count _secondary) - 1) do {
        private _cfg = _secondary select _i;
        if (isClass _cfg) then {
            private _p = getArray (_cfg >> "ilsPosition");
            if (count _p >= 2) then { _fields pushBack [_i + 1, [_p select 0, _p select 1, 0]]; };
        };
    };
};

AIC_ns set ["airfields", _fields];
AIC_ns set ["airfieldsRead", true];
["airfields: %1 has %2 airfield(s)", [worldName, count _fields]] call AIC_fnc_log;

_fields
