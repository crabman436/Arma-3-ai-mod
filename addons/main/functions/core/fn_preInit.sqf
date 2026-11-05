/*
    Function: AIC_fnc_preInit

    Description:
        Creates the mod's namespace AIC_ns: one global HashMap that holds
        all mod-wide state. Runs once on every machine before mission
        objects initialise (CfgFunctions preInit = 1). Core entry points call
        it again lazily (if (isNil "AIC_ns") then { call AIC_fnc_preInit; };),
        so it is idempotent: existing keys are kept, missing keys are added.

        Keys:
            "commanders"       - HashMap: side -> commander HashMap
            "objectiveModules" - array of AIC_ModuleObjective logics
            "debug"            - bool, default false (systemChat logging)
            "version"          - string, mod version "1.0.0"
            "cmds"             - HashMap of AIC_fnc_cmdTable (commands
                                 AIC_fnc_do may send to another machine)
            "hcIntel", "hcStats", "hcOwnersCache", "hcKnownCache" -
                                 headless-client reports (AIC_fnc_hcReport)
            "defaultSettings"  - HashMap of AIC_fnc_defaultSettings, built
                                 once; read only by AIC_fnc_getSetting
                                 (never modify it)
            "jev"              - HashMap, state of the Jev decision-model
                                 client (CONTRACT.md, "Jev extension"):
                                 "available" (bool), "reason" (string),
                                 "ehId" (number, -1 = no EH yet),
                                 "pending" (id -> request), "answered"
                                 (tag -> answers), "nextId" (number),
                                 "stats" ({"asked","answered","failed","tokens"})

    Parameters:
        None

    Returns:
        HashMap - AIC_ns

    Example:
        Called automatically by the engine.
        if (isNil "AIC_ns") then { call AIC_fnc_preInit; };
*/

if (isNil "AIC_ns" || { !(AIC_ns isEqualType createHashMap) }) then {
    AIC_ns = createHashMap;
};

if !((AIC_ns getOrDefault ["commanders", 0]) isEqualType createHashMap) then {
    AIC_ns set ["commanders", createHashMap];
};
if !((AIC_ns getOrDefault ["objectiveModules", 0]) isEqualType []) then {
    AIC_ns set ["objectiveModules", []];
};
if !((AIC_ns getOrDefault ["debug", 0]) isEqualType true) then {
    AIC_ns set ["debug", false];
};
if !((AIC_ns getOrDefault ["jev", 0]) isEqualType createHashMap) then {
    AIC_ns set ["jev", createHashMapFromArray [
        ["available", false],
        ["reason", "not initialised"],
        ["ehId", -1],
        ["pending", createHashMap],
        ["answered", createHashMap],
        ["nextId", 1],
        ["stats", createHashMapFromArray [["asked", 0], ["answered", 0], ["failed", 0], ["tokens", 0]]]
    ]];
};
AIC_ns set ["version", "1.0.0"];
// cached defaults for AIC_fnc_getSetting (rebuilt every preInit, so a changed
// AIC_fnc_defaultSettings always wins)
AIC_ns set ["defaultSettings", [] call AIC_fnc_defaultSettings];
// AI commands AIC_fnc_do may run on a group's owner (also the whitelist
// of AIC_fnc_execCmd on headless clients)
AIC_ns set ["cmds", [] call AIC_fnc_cmdTable];

AIC_ns
