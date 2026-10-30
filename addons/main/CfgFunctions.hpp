class CfgFunctions
{
    class AIC
    {
        tag = "AIC";

        class core
        {
            file = "\z\aic\addons\main\functions\core";
            class preInit { preInit = 1; };
            class createCommander {};
            class removeCommander {};
            class getCommander {};
            class getSetting {};
            class defaultSettings {};
            class commanderLoop {};
            class commanderCycle {};
            class log {};
            class moduleCommander {};
            class moduleObjective {};
        };

        class groups
        {
            file = "\z\aic\addons\main\functions\groups";
            class registerGroups {};
            class classifyGroup {};
            class groupPower {};
            class updateGroups {};
            class availableGroups {};
            class attachGroupEHs {};
            class groupEngaged {};
            class vehicleType {};
            class vehicleWeapons {};
        };

        class intel
        {
            file = "\z\aic\addons\main\functions\intel";
            class gatherIntel {};
            class clusterThreats {};
            class collectObjectives {};
            class addObjective {};
            class getObjective {};
            class updateObjectives {};
        };

        class strategy
        {
            file = "\z\aic\addons\main\functions\strategy";
            class determineStance {};
            class scoreObjectives {};
            class allocateForces {};
        };

        class orders
        {
            file = "\z\aic\addons\main\functions\orders";
            class issueOrder {};
            class clearWaypoints {};
            class orderAttack {};
            class orderDefend {};
            class orderPatrol {};
            class orderRetreat {};
            class orderReinforce {};
            class monitorOrders {};
            class roadPos {};
            class waterPos {};
            class garrisonBuildings {};
            class monitorGarrison {};
        };

        class support
        {
            file = "\z\aic\addons\main\functions\support";
            class supportCycle {};
            class fireMission {};
            class tasksAir {};
            class artilleryMagScore {};
        };

        class logistics
        {
            file = "\z\aic\addons\main\functions\logistics";
            class setGroupSim {};
            class dynSimCycle {};
            class garrisonStatus {};
            class canLeaveGarrison {};
            class garrisonCycle {};
            class findTransport {};
            class orderTransport {};
            class transportCycle {};
            class cleanupCycle {};
            class deleteHelipads {};
            class deleteGroup {};
        };

        class ui
        {
            file = "\z\aic\addons\main\functions\ui";
            class report {};
            class updateDebugMarkers {};
            class sideColor {};
            class sideMessage {};
        };
    };
};
