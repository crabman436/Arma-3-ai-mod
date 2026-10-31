/*
    Function: AIC_fnc_moduleAttr

    Description:
        Reads an Eden module attribute from a module logic and normalises
        it to the type of the given default (Eden can store a number as a
        string, a checkbox as 0 / 1, ...). The one attribute rule shared by
        AIC_fnc_moduleCommander, AIC_fnc_moduleObjective and
        AIC_fnc_collectObjectives, so every reader of a module agrees on
        the value.
          - NUMBER default: numbers as they are, strings via parseNumber,
            booleans as 0 / 1, anything else the default
          - BOOL default: booleans as they are, numbers > 0, strings
            "true" / "1" (case-insensitive), anything else the default
          - STRING default: strings as they are, anything else via str

    Parameters:
        0: OBJECT   - module logic
        1: STRING   - attribute (variable) name, e.g. "Radius"
        2: ANYTHING - default, also decides the returned type

    Returns:
        ANYTHING - the normalised value, same type as the default

    Example:
        private _radius = [_logic, "Radius", 300] call AIC_fnc_moduleAttr;
        private _isBase = [_logic, "IsBase", false] call AIC_fnc_moduleAttr;
*/

params [["_logic", objNull, [objNull]], ["_name", "", [""]], "_default"];

if (isNil "_default") exitWith { nil };
if (isNull _logic || { _name isEqualTo "" }) exitWith { _default };

private _value = _logic getVariable _name;
if (isNil "_value") exitWith { _default };

switch (true) do {
    case (_default isEqualType 0): {
        if (_value isEqualType 0) exitWith { _value };
        if (_value isEqualType "") exitWith { parseNumber _value };
        if (_value isEqualType true) exitWith { [0, 1] select _value };
        _default
    };
    case (_default isEqualType true): {
        if (_value isEqualType true) exitWith { _value };
        if (_value isEqualType 0) exitWith { _value > 0 };
        if (_value isEqualType "") exitWith { (toLowerANSI _value) in ["true", "1"] };
        _default
    };
    case (_default isEqualType ""): {
        if (_value isEqualType "") exitWith { _value };
        str _value
    };
    default { _value };
}
