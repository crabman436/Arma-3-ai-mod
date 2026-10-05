class CfgPatches {
    class cai_main {
        name = "Coordinated AI";
        author = "crabman436";
        url = "https://github.com/crabman436/Arma-3-ai-mod";
        requiredVersion = 2.10;
        requiredAddons[] = {"A3_Functions_F", "A3_Modules_F"};
        units[] = {"CAI_ModuleSettings", "CAI_ModuleExclude", "CAI_ModuleCommander"};
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
            class grabVehicles {};
            class fireAndManeuver {};
            class throwSmoke {};
            class requestArtillery {};
            class skillFloor {};
            class moduleSettings {};
            class moduleExclude {};
            class moduleCommander {};
            class commander {};
            class cmdAssess {};
            class cmdOrder {};
            class cmdGarrison {};
            class cmdRadio {};
            class cmdFires {};
            class cmdAir {};
            class isAA {};
            class fireMission {};
            class landPos {};
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
            class Default;
            class Edit;
            class Combo;
            class Checkbox;
            class CheckboxNumber;
            class ModuleDescription;
            class Units;
        };
        class ModuleDescription {
            class AnyBrain;
        };
    };

    class CAI_ModuleSettings: Module_F {
        scope = 2;
        displayName = "Coordinated AI Settings";
        icon = "\a3\ui_f\data\igui\cfg\simpletasks\types\radio_ca.paa";
        category = "CAI_Modules";
        function = "CAI_fnc_moduleSettings";
        functionPriority = 1;
        isGlobal = 1;
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
            description = "An AI commander that takes or holds the module's area with the groups synced to it (or all free groups of its side nearby). Resize the area in the editor. Sync a trigger to start it later.";
            sync[] = {"AnyBrain"};
        };
    };
};
