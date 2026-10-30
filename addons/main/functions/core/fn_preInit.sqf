/*
    Function: AIC_fnc_preInit

    Description:
        Runs once on every machine before mission objects initialise
        (CfgFunctions preInit = 1). Creates the AIC global state so that
        module functions and scripts can rely on it existing.

    Parameters:
        None

    Returns:
        Nothing

    Example:
        Called automatically by the engine.
*/

if (isNil "AIC_commanders") then { AIC_commanders = createHashMap; };
if (isNil "AIC_objectiveModules") then { AIC_objectiveModules = []; };
if (isNil "AIC_debug") then { AIC_debug = false; };

nil
