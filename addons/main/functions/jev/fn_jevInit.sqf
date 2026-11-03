/*
    Function: AIC_fnc_jevInit

    Description:
        Probes the native extension "aic_jev" (server only) and records the
        result in AIC_ns "jev": "available" (bool), "reason" (string) and
        "probeTime". The extension is present when
        "aic_jev" callExtension "version" returns a non-empty string; it is
        usable when its "status" command does not answer "nokey". Installs
        the "ExtensionCallback" mission event handler once (its id is kept
        in "ehId"; the handler only forwards "aic_jev" events to
        AIC_fnc_jevCallback). Idempotent: every call re-probes, so a key set
        at runtime ("setKey") or a late-loaded extension is picked up; the
        availability is logged only when it changes.
        Called by AIC_fnc_createCommander when "jevEnabled" is on and
        lazily by AIC_fnc_jevAsk (at most every AIC_JEV_REPROBE s while
        unavailable). Everything keeps working without the extension.

    Parameters:
        None

    Returns:
        BOOL - true when Jev can be asked (extension loaded and key found)

    Example:
        private _ok = [] call AIC_fnc_jevInit;
*/

#include "\z\aic\addons\main\script_component.hpp"

if (!isServer) exitWith { false };

if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _jev = AIC_ns getOrDefault ["jev", createHashMap];
if (!(_jev isEqualType createHashMap) || { count _jev == 0 }) then {
    call AIC_fnc_preInit;
    _jev = AIC_ns get "jev";
};

private _wasAvailable = _jev getOrDefault ["available", false];
private _oldReason = _jev getOrDefault ["reason", ""];

// --- presence: the string form returns "" when no extension of that name is loaded
private _version = AIC_JEV_EXT callExtension "version";
if !(_version isEqualType "") then { _version = ""; };

private _available = false;
private _reason = "";
if (_version isEqualTo "") then {
    _reason = "extension not loaded (aic_jev_x64.dll / .so missing next to mod.cpp)";
} else {
    // --- key: the extension looks for setKey / TYPESAFE_API_KEY / aic_jev.key itself
    private _status = "";
    private _statusCode = 0;
    private _result = AIC_JEV_EXT callExtension ["status", []];
    if (_result isEqualType []) then {
        _result params [["_text", "", [""]], ["_code", 0, [0]]];
        _status = _text;
        _statusCode = _code;
    };
    if (_statusCode != 0) then {
        _reason = format ["extension %1 loaded but 'status' failed (callExtension error %2)", _version, _statusCode];
    } else {
        if (_status isEqualTo "nokey") then {
            _reason = format ["extension %1 loaded but no API key (set TYPESAFE_API_KEY, aic_jev.key or call setKey)", _version];
        } else {
            _available = true;
            _reason = format ["extension %1, status %2", _version, _status];
        };
    };
};

_jev set ["available", _available];
_jev set ["reason", _reason];
_jev set ["probeTime", time];

// --- answers arrive through the engine's extension callback; install the handler once
if ((_jev getOrDefault ["ehId", -1]) < 0) then {
    private _ehId = addMissionEventHandler ["ExtensionCallback", {
        params [["_name", "", [""]]];
        if (_name isEqualTo AIC_JEV_EXT) then { _this call AIC_fnc_jevCallback; };
    }];
    _jev set ["ehId", _ehId];
};

if (_available isNotEqualTo _wasAvailable || { _reason isNotEqualTo _oldReason }) then {
    ["Jev %1: %2", [["unavailable", "available"] select _available, _reason]] call AIC_fnc_log;
};

_available
