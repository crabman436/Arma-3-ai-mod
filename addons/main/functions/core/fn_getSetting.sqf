/*
    Function: AIC_fnc_getSetting

    Description:
        Reads a setting of a commander. Falls back to the default value
        (AIC_fnc_defaultSettings) if the commander has no such key, or if the
        stored value has a different type than the default (settings can be
        edited live in the commander HashMap). Callers can therefore rely on
        the type and need no fallback literals of their own; range checks
        (e.g. "> 0") stay with the caller.
        The defaults are built once and cached in AIC_ns "defaultSettings"
        (AIC_fnc_preInit). Keys without a default are returned unchecked.

    Parameters:
        0: HASHMAP - commander (an empty HashMap reads the defaults)
        1: STRING  - setting key, e.g. "loopInterval"

    Returns:
        ANYTHING - setting value (nil if the key is unknown everywhere)

    Example:
        private _interval = [_cmd, "loopInterval"] call AIC_fnc_getSetting;
*/

params [["_cmd", createHashMap, [createHashMap]], ["_key", "", [""]]];

if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
private _defaults = AIC_ns getOrDefault ["defaultSettings", createHashMap];
if (!(_defaults isEqualType createHashMap) || { count _defaults == 0 }) then {
    _defaults = [] call AIC_fnc_defaultSettings;
    AIC_ns set ["defaultSettings", _defaults];
};

private _settings = _cmd getOrDefault ["settings", createHashMap];
if !(_settings isEqualType createHashMap) then { _settings = createHashMap; };

private _default = _defaults get _key;
if !(_key in _settings) exitWith { _default };

private _value = _settings get _key;
if (isNil "_default") exitWith { _value };
if (isNil "_value" || { !(_value isEqualType _default) }) exitWith { _default };
_value
