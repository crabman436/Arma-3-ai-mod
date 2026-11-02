/*
    Function: AIC_fnc_jevInit

    Description:
        Checks once per mission (server only) whether the general can be
        briefed: the aic_jev extension must be loaded and must have an API
        key (TYPESAFE_API_KEY or aic_jev.cfg on the server). If so, adds the
        ExtensionCallback mission event handler that delivers Jev's answers
        to AIC_fnc_jevOnAnswer. The result is cached in AIC_ns ("jevChecked",
        "jevReady"); a missing extension or key is logged once and the
        commanders keep running on their formulas. A key added later needs a
        mission restart.

    Parameters:
        None

    Returns:
        BOOL - true if briefings can be sent

    Example:
        if ([] call AIC_fnc_jevInit) then { ... };
*/

if (!isServer) exitWith { false };
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };

if ((AIC_ns getOrDefault ["jevChecked", false]) isEqualTo true) exitWith {
    (AIC_ns getOrDefault ["jevReady", false]) isEqualTo true
};
AIC_ns set ["jevChecked", true];
AIC_ns set ["jevReady", false];
AIC_ns set ["jevRequests", createHashMap];

private _version = ("aic_jev" callExtension ["version", []]) param [0, ""];
if (_version isEqualTo "") exitWith {
    ["JEV: extension aic_jev is not loaded on the server; generals keep using their formulas", []] call AIC_fnc_log;
    false
};

private _ready = ("aic_jev" callExtension ["ready", []]) param [0, ""];
if !(_ready isEqualTo "ok") exitWith {
    ["JEV: aic_jev %1 is loaded but has no API key (set TYPESAFE_API_KEY or api_key in aic_jev.cfg); generals keep using their formulas", [_version]] call AIC_fnc_log;
    false
};

addMissionEventHandler ["ExtensionCallback", {
    params ["_name", "_function", "_data"];
    if (_name isEqualTo "aic_jev") then {
        [_function, _data] call AIC_fnc_jevOnAnswer;
    };
}];

AIC_ns set ["jevReady", true];
["JEV: aic_jev %1 ready, generals will be briefed", [_version]] call AIC_fnc_log;
true
