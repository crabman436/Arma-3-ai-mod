class CfgPatches {
    class cai_main {
        name = "Coordinated AI";
        author = "crabman436";
        url = "https://github.com/crabman436/Arma-3-ai-mod";
        requiredVersion = 2.10;
        requiredAddons[] = {"A3_Functions_F", "A3_Modules_F"};
        units[] = {"CAI_ModuleSettings", "CAI_ModuleExclude", "CAI_ModuleCommander", "CAI_ModuleStaging", "CAI_ModuleAttackPos", "CAI_ModuleObjective", "CAI_ModuleGarrison", "CAI_ModuleClear"};
        weapons[] = {};
    };
};

class CfgFunctions {
    class CAI {
        tag = "CAI";
        class core {
            file = "\z\cai\addons\main\functions";
            class settings { preInit = 1; };
            class init { postInit = 1; };
            class log {};
            class isValidGroup {};
            class groupType {};
            class dismount {};
            class releaseGroup {};
            class splitOff {};
            class threatValue {};
            class revealTo {};
            class processGroup {};
            class shareIntel {};
            class alertNearby {};
            class requestSupport {};
            class isAvailableResponder {};
            class dispatchResponder {};
            class returnHome {};
            class clearWaypoints {};
            class addWaypoint {};
            class saveHome {};
            class flankPosition {};
            class findTransport {};
            class airLift {};
            class groundLift {};
            class grabVehicles {};
            class fireAndManeuver {};
            class keepSpacing {};
            class throwSmoke {};
            class requestArtillery {};
            class skillFloor {};
            class moduleSettings {};
            class moduleExclude {};
            class moduleCommander {};
            class modulePlanPoint {};
            class commander {};
            class cmdAssess {};
            class cmdOrder {};
            class buildingsIn {};
            class garrison {};
            class clearBuildings {};
            class moduleGarrison {};
            class moduleClear {};
            class cmdRadio {};
            class cmdFires {};
            class cmdAir {};
            class isAA {};
            class fireMission {};
            class landPos {};
            class pickPos {};
            class paraDrop {};
            class selectResponders {};
            class activeResponders {};
            class markContact {};
            class playerContactEH {};
            class playerActions {};
            class playerRequest {};
            class boundAdvance {};
        };
    };
};

class CfgFactionClasses {
    class NO_CATEGORY;
    class CAI_Modules: NO_CATEGORY {
        displayName = "Coordinated AI";
    };
};

class CfgVehicles {
    class Logic;
    class Module_F: Logic {
        class AttributesBase {
            class Edit;
            class Combo;
            class Checkbox;
            class ModuleDescription;
        };
        class ModuleDescription;
    };

    class CAI_ModuleSettings: Module_F {
        scope = 2;
        scopeCurator = 0;
        displayName = "Coordinated AI Settings";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\radio_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_moduleSettings";
        functionPriority = 1;
        isGlobal = 2;
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;

        class Attributes: AttributesBase {
            class Enabled: Checkbox {
                property = "CAI_ModuleSettings_Enabled";
                displayName = "Enabled";
                tooltip = "Turn the Coordinated AI system on or off for this mission.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class Debug: Checkbox {
                property = "CAI_ModuleSettings_Debug";
                displayName = "Debug messages";
                tooltip = "Show what the AI is doing in system chat (intel shared, QRFs sent, flanks...).";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class ShareRadius: Edit {
                property = "CAI_ModuleSettings_ShareRadius";
                displayName = "Intel share radius (m)";
                tooltip = "Groups within this distance of a group in contact receive its spotted targets over the radio.";
                typeName = "NUMBER";
                defaultValue = "1500";
            };
            class InfantryRadius: Edit {
                property = "CAI_ModuleSettings_InfantryRadius";
                displayName = "Infantry QRF radius (m)";
                tooltip = "Idle infantry within this distance can be sent to help (on foot, or by vehicle / helicopter if available).";
                typeName = "NUMBER";
                defaultValue = "1200";
            };
            class VehicleRadius: Edit {
                property = "CAI_ModuleSettings_VehicleRadius";
                displayName = "Ground vehicle QRF radius (m)";
                tooltip = "Idle cars, APCs and tanks within this distance can be sent to engage spotted enemies.";
                typeName = "NUMBER";
                defaultValue = "3000";
            };
            class AirRadius: Edit {
                property = "CAI_ModuleSettings_AirRadius";
                displayName = "Air QRF radius (m)";
                tooltip = "Idle attack helicopters (and transport helicopters for air lifts) within this distance can respond.";
                typeName = "NUMBER";
                defaultValue = "6000";
            };
            class MaxResponders: Edit {
                property = "CAI_ModuleSettings_MaxResponders";
                displayName = "Max responders per fight";
                tooltip = "How many groups at most can be sent to help a single group in contact.";
                typeName = "NUMBER";
                defaultValue = "3";
            };
            class AirLift: Checkbox {
                property = "CAI_ModuleSettings_AirLift";
                displayName = "Helicopter air lifts";
                tooltip = "Idle transport helicopters fly far-away infantry QRFs to a landing zone near the fight.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class TruckLift: Checkbox {
                property = "CAI_ModuleSettings_TruckLift";
                displayName = "Truck transport";
                tooltip = "Idle crewed unarmed vehicles with seats (trucks, unarmed cars) drive infantry to the fight and drop them off short of it. Also used by the commander.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class PlayerRequests: Checkbox {
                property = "CAI_ModuleSettings_PlayerRequests";
                displayName = "Player support requests";
                tooltip = "Players get two action-menu entries: a fire mission on the point they aim at, and reinforcements to that point (the best available AI groups respond). With cooldowns.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class UseJets: Checkbox {
                property = "CAI_ModuleSettings_UseJets";
                displayName = "Jets respond";
                tooltip = "Allow idle armed planes to respond with close air support.";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class Maneuver: Checkbox {
                property = "CAI_ModuleSettings_Maneuver";
                displayName = "Fire and maneuver";
                tooltip = "Infantry squads split into a base of fire and a flanking team.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class Spacing: Edit {
                property = "CAI_ModuleSettings_Spacing";
                displayName = "Firefight spacing (m)";
                tooltip = "In a firefight, soldiers closer than this to a squadmate spread out sideways along the firing line (to cover if there is some), squads on top of each other side-step, and squads in open ground use a line facing the enemy. 0 = off.";
                typeName = "NUMBER";
                defaultValue = "5";
            };
            class Artillery: Checkbox {
                property = "CAI_ModuleSettings_Artillery";
                displayName = "Artillery / mortar support";
                tooltip = "Idle friendly mortars and artillery fire on well-located enemies (never danger close).";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class SkillFloor: Checkbox {
                property = "CAI_ModuleSettings_SkillFloor";
                displayName = "Raise teamwork skills";
                tooltip = "Raise commanding, spotting and courage to a minimum level. Never lowers skills and does not touch aiming.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Optional. Place once to tune Coordinated AI. Without this module the mod runs with default settings.";
        };
    };

    class CAI_ModuleExclude: Module_F {
        scope = 2;
        scopeCurator = 0;
        displayName = "Coordinated AI Exclude Groups";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\danger_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_moduleExclude";
        functionPriority = 2;
        isGlobal = 0;
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;

        class Attributes: AttributesBase {
            class Mode: Combo {
                property = "CAI_ModuleExclude_Mode";
                displayName = "Mode";
                tooltip = "What to exclude the synced groups from.";
                typeName = "NUMBER";
                defaultValue = "0";
                class Values {
                    class All { name = "Ignore completely"; value = 0; };
                    class NoQRF { name = "Never send as QRF (still shares intel and fights smart)"; value = 1; };
                };
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Sync units to this module to exclude their groups from Coordinated AI, or just stop them from being sent away as reinforcements.";
            sync[] = {"AnyBrain"};
        };
    };

    class CAI_ModuleCommander: Module_F {
        scope = 2;
        scopeCurator = 0;
        displayName = "Coordinated AI Commander";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\attack_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_moduleCommander";
        functionPriority = 3;
        isGlobal = 0;
        isTriggerActivated = 1;
        isDisposable = 0;
        is3DEN = 0;
        canSetArea = 1;
        canSetAreaShape = 0;

        class AttributeValues {
            size3[] = {250, 250, -1};
            isRectangle = 0;
        };

        class Attributes: AttributesBase {
            class Mode: Combo {
                property = "CAI_ModuleCommander_Mode";
                displayName = "Mission";
                tooltip = "Attack: take the area. Defend: hold it. An attacker that takes the area switches to defending it, and a defender that loses it counter-attacks.";
                typeName = "NUMBER";
                defaultValue = "0";
                class Values {
                    class Attack { name = "Attack / take the area"; value = 0; };
                    class Defend { name = "Defend / hold the area"; value = 1; };
                };
            };
            class Side: Combo {
                property = "CAI_ModuleCommander_Side";
                displayName = "Side";
                tooltip = "Which side this commander leads. 'From synced groups' uses the side of the first synced group.";
                typeName = "NUMBER";
                defaultValue = "-1";
                class Values {
                    class Auto { name = "From synced groups"; value = -1; };
                    class West { name = "BLUFOR"; value = 0; };
                    class East { name = "OPFOR"; value = 1; };
                    class Indep { name = "Independent"; value = 2; };
                };
            };
            class Tempo: Combo {
                property = "CAI_ModuleCommander_Tempo";
                displayName = "Attack tempo";
                tooltip = "Fast: squads go straight to their attack positions (no gathering at a staging area), short preparatory fires, H-hour after at most 90 s. Normal: gather at the staging area first (up to 4 min), H-hour after at most 3 min. Deliberate: long gather, long preparation, everyone in position before H-hour.";
                typeName = "NUMBER";
                defaultValue = "0";
                class Values {
                    class Fast { name = "Fast"; value = 0; };
                    class Normal { name = "Normal"; value = 1; };
                    class Deliberate { name = "Deliberate"; value = 2; };
                };
            };
            class Style: Combo {
                property = "CAI_ModuleCommander_Style";
                displayName = "Assault style";
                tooltip = "Dispersed: every squad gets its own lane, spread around the objective, and attacks as soon as it is in position (many small attacks from different sides). Coordinated: up to three lanes and everyone goes together at H-hour (one big push).";
                typeName = "NUMBER";
                defaultValue = "0";
                class Values {
                    class Dispersed { name = "Dispersed (each squad attacks on its own)"; value = 0; };
                    class Coordinated { name = "Coordinated (one push at H-hour)"; value = 1; };
                };
            };
            class AutoRadius: Edit {
                property = "CAI_ModuleCommander_AutoRadius";
                displayName = "Auto-assign radius (m)";
                tooltip = "Only used when no groups are synced: every free AI group of the side within this distance is put under command.";
                typeName = "NUMBER";
                defaultValue = "2000";
            };
            class Reserve: Edit {
                property = "CAI_ModuleCommander_Reserve";
                displayName = "Reserve (%)";
                tooltip = "Share of infantry squads held back during an attack and committed when the assault stalls.";
                typeName = "NUMBER";
                defaultValue = "25";
            };
            class FireSupport: Combo {
                property = "CAI_ModuleCommander_FireSupport";
                displayName = "Fire support";
                tooltip = "How hard the commander uses friendly mortars and artillery: preparatory barrages, continuous fire on spotted enemies (AA and armor first), smoke screens for the assault and illumination at night. Never danger close.";
                typeName = "NUMBER";
                defaultValue = "1";
                class Values {
                    class Off { name = "Off"; value = 0; };
                    class Normal { name = "Normal"; value = 1; };
                    class Heavy { name = "Heavy (double rounds, faster missions)"; value = 2; };
                };
            };
            class Bombard: Combo {
                property = "CAI_ModuleCommander_Bombard";
                displayName = "Bombard before the attack";
                tooltip = "Attack only. Before the assault goes in, the commander's mortars and artillery shell the buildings of the objective whether or not enemies have been seen there, then the troops move in. Never danger close to friendly troops.";
                typeName = "NUMBER";
                defaultValue = "0";
                class Values {
                    class Off { name = "Off"; value = 0; };
                    class Light { name = "Short bombardment (1.5 min)"; value = 1; };
                    class Heavy { name = "Level it (4 min)"; value = 2; };
                };
            };
            class AirSupport: Checkbox {
                property = "CAI_ModuleCommander_AirSupport";
                displayName = "Air support";
                tooltip = "Commanded attack helicopters and jets fly strike missions on the most valuable spotted targets. Helicopters hold back while enemy anti-air is alive.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class Refit: Checkbox {
                property = "CAI_ModuleCommander_Refit";
                displayName = "Aircraft rearm at base";
                tooltip = "Aircraft that run out of ammo or fuel, or are badly damaged, fly back to where they started, get rearmed, refueled and repaired after 90 seconds, then return to the fight.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AirAssault: Combo {
                property = "CAI_ModuleCommander_AirAssault";
                displayName = "Helicopter air assault";
                tooltip = "Attack only. When the attack forms up, each transport helicopter under this commander picks up an infantry squad and waits. At H-hour they fly in low and fast, land at tight landing zones close to the objective and unload hot, while gunships escort the landing zones. Edge: just outside the objective. Into: inside it.";
                typeName = "NUMBER";
                defaultValue = "0";
                class Values {
                    class Off { name = "Off"; value = 0; };
                    class Edge { name = "Edge of the objective"; value = 1; };
                    class Into { name = "Into the objective (hot LZ)"; value = 2; };
                };
            };
            class Paradrop: Combo {
                property = "CAI_ModuleCommander_Paradrop";
                displayName = "Opening paradrop";
                tooltip = "Attack only. When the attack forms up, each transport helicopter or transport plane under this commander loads one infantry squad (or uses one already aboard). When the preparatory fires start they fly over the drop zone and the squad jumps. Onto the objective: shock drop straight into it. Behind it: cuts it off, then assaults from the rear at H-hour.";
                typeName = "NUMBER";
                defaultValue = "0";
                class Values {
                    class Off { name = "Off"; value = 0; };
                    class Onto { name = "Onto the objective (shock drop)"; value = 1; };
                    class Behind { name = "Behind the objective (cut it off)"; value = 2; };
                };
            };
            class ClearBuildings: Checkbox {
                property = "CAI_ModuleCommander_ClearBuildings";
                displayName = "Clear buildings";
                tooltip = "Attack: once in the objective, squads clear its buildings room by room, and the objective only counts as secured when most buildings are cleared. Defend: reserves sweep the buildings after enemies got inside.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class Radio: Checkbox {
                property = "CAI_ModuleCommander_Radio";
                displayName = "Radio messages";
                tooltip = "Players on this side hear the commander's orders in side chat.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class Markers: Checkbox {
                property = "CAI_ModuleCommander_Markers";
                displayName = "Map markers";
                tooltip = "Show the objective area and the commander's current status on the map.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "An AI commander that takes or holds the module's area with the groups synced to it (or all free groups of its side nearby). Resize the area in the editor. Sync a trigger to start it later. Optional: sync a Staging Area, Attack Position(s) and Objective modules to it to plan the attack yourself.";
            sync[] = {"AnyBrain"};
        };
    };

    class CAI_ModuleStaging: Module_F {
        scope = 2;
        scopeCurator = 0;
        displayName = "Coordinated AI Commander: Staging Area";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\meet_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_modulePlanPoint";
        functionPriority = 1;
        isGlobal = 0;
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;

        class Attributes: AttributesBase {
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Sync to a Commander (or to one of its Objective modules): the force forms up here and attacks from this side. Reserve and squads that fall back also gather here.";
        };
    };

    class CAI_ModuleAttackPos: Module_F {
        scope = 2;
        scopeCurator = 0;
        displayName = "Coordinated AI Commander: Attack Position";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\attack_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_modulePlanPoint";
        functionPriority = 1;
        isGlobal = 0;
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;

        class Attributes: AttributesBase {
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Sync one or more to a Commander (or to one of its Objective modules). Each one is an assault lane: squads form up here and attack the objective from this spot. Squads are shared out between the positions, left to right.";
        };
    };

    class CAI_ModuleObjective: Module_F {
        scope = 2;
        scopeCurator = 0;
        displayName = "Coordinated AI Commander: Objective";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\target_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_modulePlanPoint";
        functionPriority = 1;
        isGlobal = 0;
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;
        canSetArea = 1;
        canSetAreaShape = 0;

        class AttributeValues {
            size3[] = {200, 200, -1};
            isRectangle = 0;
        };

        class Attributes: AttributesBase {
            class Order: Edit {
                property = "CAI_ModuleObjective_Order";
                displayName = "Order";
                tooltip = "Objectives are taken one after another, lowest number first, after the commander's own area.";
                typeName = "NUMBER";
                defaultValue = "1";
            };
            class LeaveGarrison: Checkbox {
                property = "CAI_ModuleObjective_LeaveGarrison";
                displayName = "Leave a garrison behind";
                tooltip = "When the force moves on to this objective, one infantry squad stays to garrison the one just taken.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Sync to a Commander: once its area is taken, the force moves on and attacks this area next (several objectives are taken in Order). Defends the last one. Sync a Staging Area and Attack Positions to this module to plan that attack too.";
        };
    };

    class CAI_ModuleGarrison: Module_F {
        scope = 2;
        scopeCurator = 0;
        displayName = "Coordinated AI Garrison";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\defend_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_moduleGarrison";
        functionPriority = 4;
        isGlobal = 0;
        isTriggerActivated = 1;
        isDisposable = 0;
        is3DEN = 0;
        canSetArea = 1;
        canSetAreaShape = 0;

        class AttributeValues {
            size3[] = {75, 75, -1};
            isRectangle = 0;
        };

        class Attributes: AttributesBase {
            class Facing: Combo {
                property = "CAI_ModuleGarrison_Facing";
                displayName = "Watch";
                tooltip = "All-round, or concentrate on the direction the module is facing (rotate it in the editor).";
                typeName = "NUMBER";
                defaultValue = "0";
                class Values {
                    class AllRound { name = "All-round"; value = 0; };
                    class Facing { name = "Module facing direction"; value = 1; };
                };
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Synced squads garrison the buildings in the area: soldiers take window and rooftop positions with a view, crouch or stand to see out, watch their sector and hold. Anyone with an enemy right on top of them is released to fight.";
            sync[] = {"AnyBrain"};
        };
    };

    class CAI_ModuleClear: Module_F {
        scope = 2;
        scopeCurator = 0;
        displayName = "Coordinated AI Clear Area";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\search_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_moduleClear";
        functionPriority = 4;
        isGlobal = 0;
        isTriggerActivated = 1;
        isDisposable = 0;
        is3DEN = 0;
        canSetArea = 1;
        canSetAreaShape = 0;

        class AttributeValues {
            size3[] = {150, 150, -1};
            isRectangle = 0;
        };

        class Attributes: AttributesBase {
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription {
            description = "Synced squads clear every building in the area room by room: security outside, an entry team inside, frag first if an enemy is known inside. Squads split the buildings between them. Sync a trigger to start later.";
            sync[] = {"AnyBrain"};
        };
    };
};
