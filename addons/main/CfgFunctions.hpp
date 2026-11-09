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
            class requestReplan {};
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
            class refillGroup {};
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
            class garrisonPath {};
            class monitorGarrison {};
            class garrisonLayout {};
            class garrisonPost {};
            class garrisonVehicles {};
            class monitorVehiclePosts {};
            class vehiclePostWatch {};
            class holdVehicle {};
            class releaseVehicle {};
            class rallySpot {};
            class suppressFor {};
            class suppressWatch {};
            class sentryWatch {};
            class alarmPos {};
            class orderAssault {};
            class bestPlace {};
            class setMarch {};
            class splitForAttack {};
            class orderRecon {};
            class rallyPoint {};
            class queueOrder {};
            class drainOrders {};
            class queuedGroups {};
        };

        class support
        {
            file = "\z\aic\addons\main\functions\support";
            class supportCycle {};
            class onRunway {};
            class flyingWeather {};
            class fireMission {};
            class tasksAir {};
            class airDefence {};
            class airfields {};
            class heldAirfield {};
            class rearmCycle {};
            class artilleryMagScore {};
            class timeToNight {};
        };

        class logistics
        {
            file = "\z\aic\addons\main\functions\logistics";
            class setGroupSim {};
            class heliInsert {};
            class fastRope {};
            class ropeOrigins {};
            class ropeHeights {};
            class ropePoint {};
            class cacheCycle {};
            class cacheGroup {};
            class uncacheGroup {};
            class dynSimCycle {};
            class garrisonStatus {};
            class canLeaveGarrison {};
            class garrisonCycle {};
            class recoverCycle {};
            class dismountCarrier {};
            class parkSlot {};
            class nearestBase {};
            class supplyRoles {};
            class supplyCycle {};
            class splitForRide {};
            class paradrop {};
            class fortifyCycle {};
            class fortifyPlan {};
            class staticClasses {};
            class flightPath {};
            class isLanded {};
            class freeSeats {};
            class findTransport {};
            class orderTransport {};
            class joinRide {};
            class transportCycle {};
            class airliftFor {};
            class airliftCycle {};
            class cleanupCycle {};
            class deleteHelipads {};
            class deleteGroup {};
        };

        class jev
        {
            file = "\z\aic\addons\main\functions\jev";
            class jevInit {};
            class jevToJSON {};
            class jevAsk {};
            class jevCallback {};
            class jevAnswers {};
            class jevState {};
            class jevAdvisor {};
        };

        class hc
        {
            file = "\z\aic\addons\main\functions\hc";
            class hcInit { postInit = 1; };
            class cmdTable {};
            class do {};
            class execCmd {};
            class hcOwners {};
            class fromHC {};
            class hcBalance {};
            class hcAttach {};
            class hcLoop {};
            class hcReport {};
            class hcKnown {};
            class nearestEnemy {};
            class groupEvent {};
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
