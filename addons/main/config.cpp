class CfgPatches
{
    class AIC_main
    {
        name = "AI Commander";
        author = "AIC";
        url = "";
        units[] = {"AIC_ModuleCommander", "AIC_ModuleObjective"};
        weapons[] = {};
        requiredVersion = 2.14;
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
