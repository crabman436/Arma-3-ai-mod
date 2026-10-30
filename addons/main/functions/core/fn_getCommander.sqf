/*
    Function: AIC_fnc_getCommander

    Description:
        Returns the commander HashMap of a side.

    Parameters:
        0: SIDE - side of the commander

    Returns:
        HashMap - the commander, or an empty HashMap if the side has none
                  (check with `count _cmd == 0`)

    Example:
        private _cmd = [east] call AIC_fnc_getCommander;
        if (count _cmd > 0) then { hint (_cmd get "stance"); };
*/

params [["_side", sideUnknown, [sideUnknown]]];

if (isNil "AIC_ns") then { call AIC_fnc_preInit; };

(AIC_ns get "commanders") getOrDefault [_side, createHashMap]
