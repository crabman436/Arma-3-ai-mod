/*
    Function: AIC_fnc_getSetting

    Description:
        Reads a setting of a commander. Falls back to the default value
        (AIC_fnc_defaultSettings) if the commander has no such key.

    Parameters:
        0: HASHMAP - commander
        1: STRING  - setting key, e.g. "loopInterval"

    Returns:
        ANYTHING - setting value (nil if the key is unknown everywhere)

    Example:
        private _interval = [_cmd, "loopInterval"] call AIC_fnc_getSetting;
*/

params [["_cmd", createHashMap, [createHashMap]], ["_key", "", [""]]];

private _settings = _cmd getOrDefault ["settings", createHashMap];
if !(_settings isEqualType createHashMap) then { _settings = createHashMap; };

if (_key in _settings) exitWith { _settings get _key };

([] call AIC_fnc_defaultSettings) get _key
