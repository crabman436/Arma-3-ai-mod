/*
    Function: AIC_fnc_jevToJSON

    Description:
        Encodes an SQF value as a JSON text (recursive):
          - HashMap -> object; keys that are not strings go through str
          - array   -> array (elements of mixed types allowed)
          - string  -> string with ", \, newline, carriage return, tab,
                       backspace, form feed escaped and any other control
                       character as \u00XX (unicode passes through as is)
          - number  -> number: integers without ".0", no exponent notation
                       (very small / large values are written with toFixed
                       and trailing zeros stripped), non-finite -> null
          - bool    -> true / false
          - nil and anything else (sides, objects, groups, code) -> null

    Parameters:
        0: ANYTHING - value to encode (may be nil)

    Returns:
        STRING - JSON text (no whitespace)

    Example:
        [createHashMapFromArray [["a", 1], ["b", [true, "x" + toString [10] + "y", 0.5]], ["c", createHashMap]]] call AIC_fnc_jevToJSON
            -> {"a":1,"b":[true,"x\ny",0.5],"c":{}}        (object keys in HashMap order)
        [[1, "two", nil, [3, -4.25]]] call AIC_fnc_jevToJSON    -> [1,"two",null,[3,-4.25]]
        ["say ""hi"" \ bye"] call AIC_fnc_jevToJSON             -> "say \"hi\" \\ bye"
        [1e-05] call AIC_fnc_jevToJSON                          -> 0.00001
        [123456789] call AIC_fnc_jevToJSON                      -> 123456789
        [1 / 3] call AIC_fnc_jevToJSON                          -> 0.333333
        [west] call AIC_fnc_jevToJSON                           -> null
*/

params ["_value"];

if (isNil "_value") exitWith { "null" };

switch (true) do {
    // --- string
    case (_value isEqualType ""): {
        private _codes = toArray _value;
        // fast path: nothing to escape
        if ((_codes findIf { _x < 32 || { _x == 34 } || { _x == 92 } }) < 0) exitWith {
            """" + _value + """"
        };
        private _hex = "0123456789abcdef";
        private _parts = [];
        private _run = [];
        {
            if (_x < 32 || { _x == 34 } || { _x == 92 }) then {
                if (_run isNotEqualTo []) then {
                    _parts pushBack toString _run;
                    _run = [];
                };
                _parts pushBack (switch (_x) do {
                    case 34: { "\""" };
                    case 92: { "\\" };
                    case 10: { "\n" };
                    case 13: { "\r" };
                    case 9: { "\t" };
                    case 8: { "\b" };
                    case 12: { "\f" };
                    default { "\u00" + (_hex select [floor (_x / 16), 1]) + (_hex select [_x mod 16, 1]) };
                });
            } else {
                _run pushBack _x;
            };
        } forEach _codes;
        if (_run isNotEqualTo []) then { _parts pushBack toString _run; };
        """" + (_parts joinString "") + """"
    };

    // --- number
    case (_value isEqualType 0): {
        if (!finite _value) exitWith { "null" };
        private _abs = abs _value;
        if (_abs == 0) exitWith { "0" };
        // integers: toFixed never switches to exponent notation, str does past ~1e6
        if (_value == floor _value && { _abs < 1e15 }) exitWith { _value toFixed 0 };
        // str uses %g-style output: exponent below 1e-4 and at or above 1e6
        // (999999.5 already rounds to "1e+06"), so write those fixed instead
        if (_abs < 0.0001 || { _abs >= 1e5 }) exitWith {
            private _fixed = _value toFixed 8;
            _fixed = _fixed regexReplace ["0+$", ""];
            _fixed = _fixed regexReplace ["\.$", ""];
            // a magnitude below the 8 decimals collapses to "-0" / "0"
            [_fixed, "0"] select (_fixed in ["", "-", "-0"])
        };
        str _value
    };

    // --- boolean
    case (_value isEqualType true): {
        ["false", "true"] select _value
    };

    // --- array
    case (_value isEqualType []): {
        private _items = _value apply {
            if (isNil "_x") then { "null" } else { [_x] call AIC_fnc_jevToJSON }
        };
        "[" + (_items joinString ",") + "]"
    };

    // --- object
    case (_value isEqualType createHashMap): {
        private _pairs = [];
        {
            private _key = [str _x, _x] select (_x isEqualType "");
            private _item = if (isNil "_y") then { "null" } else { [_y] call AIC_fnc_jevToJSON };
            _pairs pushBack (([_key] call AIC_fnc_jevToJSON) + ":" + _item);
        } forEach _value;
        "{" + (_pairs joinString ",") + "}"
    };

    // --- sides, objects, groups, code, ...
    default { "null" };
}
