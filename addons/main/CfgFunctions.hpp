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
            class moduleAttr {};
        };

        class groups
        {
            file = "\z\aic\addons\main\functions\groups";
            class registerGroups {};
            class classifyGroup {};
            class newGroupRecord {};
            class splitPassengers {};
            class splitGroup {};
            class teamCycle {};
            class spreadCycle {};
            class groupPower {};
            class updateGroups {};
            class availableGroups {};
            class attachGroupEHs {};
            class groupEngaged {};
            class vehicleType {};
            class vehicleWeapons {};
            class vehicleArmament {};
            class isAntiAir {};
        };

        class intel
        {
            file = "\z\aic\addons\main\functions\intel";
            class gatherIntel {};
            class clusterThreats {};
            class collectObjectives {};
            class addObjective {};
            class getObjective {};
            class nearestThreat {};
            class updateObjectives {};
        };

        class strategy
        {
            file = "\z\aic\addons\main\functions\strategy";
            class determineStance {};
            class scoreObjectives {};
            class allocateForces {};
            class assaultFor {};
            class assaultCycle {};
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
            class sentryWatch {};
            class alarmPos {};
            class orderAssault {};
            class bestPlace {};
            class setMarch {};
            class splitForAttack {};
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
            class dismountCarrier {};
            class parkSlot {};
            class nearestBase {};
            class supplyRoles {};
            class supplyCycle {};
            class splitForRide {};
            class flightPath {};
            class isLanded {};
            class freeSeats {};
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
