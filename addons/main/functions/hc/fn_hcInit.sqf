/*
    Function: AIC_fnc_hcInit

    Description:
        postInit on every machine: starts AIC_fnc_hcLoop on a headless client
        (no interface, not the server). Does nothing elsewhere.

    Parameters:
        None

    Returns:
        Nothing

    Example:
        Called automatically by the engine (CfgFunctions postInit = 1).
*/

if (isServer || hasInterface) exitWith {};
if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
[] spawn AIC_fnc_hcLoop;
