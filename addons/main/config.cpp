class CfgPatches
{
    class AIC_main
    {
        name = "AI Commander";
        author = "AIC";
        url = "";
        units[] = {"AIC_ModuleCommander", "AIC_ModuleObjective"};
        weapons[] = {};
        requiredVersion = 2.18;
        requiredAddons[] = {"A3_Modules_F"};
    };
};

class CfgFactionClasses
{
    class NO_CATEGORY;
    class AIC_Modules: NO_CATEGORY
    {
        displayName = "AI Commander";
    };
};

#include "CfgFunctions.hpp"
#include "CfgVehicles.hpp"

// remote calls between the server and headless clients (each function also
// checks who sent it); a mission in whitelist mode must allow them too
class CfgRemoteExec
{
    class Functions
    {
        class AIC_fnc_execCmd { allowedTargets = 0; };
        class AIC_fnc_groupEvent { allowedTargets = 2; };
        class AIC_fnc_hcReport { allowedTargets = 2; };
    };
};
