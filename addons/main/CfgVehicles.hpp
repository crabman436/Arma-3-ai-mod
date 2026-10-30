class CfgVehicles
{
    class Logic;
    class Module_F: Logic
    {
        class AttributesBase
        {
            class Default;
            class Edit;
            class Combo;
            class Checkbox;
            class CheckboxNumber;
            class ModuleDescription;
            class Units;
        };
        class ModuleDescription
        {
            class AnyBrain;
        };
    };

    // ------------------------------------------------------------------
    // AI Commander: one AI general for a whole side
    // ------------------------------------------------------------------
    class AIC_ModuleCommander: Module_F
    {
        scope = 2;
        scopeCurator = 0;
        displayName = "AI Commander";
        category = "AIC_Modules";
        function = "AIC_fnc_moduleCommander";
        functionPriority = 2;      // after objective modules (priority 1)
        isGlobal = 0;              // server only
        isTriggerActivated = 1;
        isDisposable = 0;
        is3DEN = 0;

        class Attributes: AttributesBase
        {
            class Side: Combo
            {
                property = "AIC_ModuleCommander_Side";
                displayName = "Side";
                tooltip = "Side this AI general commands. All AI groups of that side come under its control.";
                typeName = "NUMBER";
                defaultValue = "1";
                class Values
                {
                    class West  { name = "BLUFOR";      value = 0; };
                    class East  { name = "OPFOR";       value = 1; default = 1; };
                    class Indep { name = "INDEPENDENT"; value = 2; };
                };
            };
            class Aggression: Edit
            {
                property = "AIC_ModuleCommander_Aggression";
                displayName = "Aggression";
                tooltip = "0..1 - biases the general toward attacking (1) or defending (0).";
                typeName = "NUMBER";
                defaultValue = "0.5";
            };
            class LoopInterval: Edit
            {
                property = "AIC_ModuleCommander_LoopInterval";
                displayName = "Think interval (s)";
                tooltip = "Seconds between commander decision cycles (minimum 5).";
                typeName = "NUMBER";
                defaultValue = "30";
            };
            class UseArtillery: Checkbox
            {
                property = "AIC_ModuleCommander_UseArtillery";
                displayName = "Use artillery";
                tooltip = "Allow the general to call fire missions with its artillery groups.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class UseAir: Checkbox
            {
                property = "AIC_ModuleCommander_UseAir";
                displayName = "Use air (CAS)";
                tooltip = "Allow the general to task helicopters and planes against threats.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AutoObjectives: Checkbox
            {
                property = "AIC_ModuleCommander_AutoObjectives";
                displayName = "Auto objectives";
                tooltip = "Add nearby towns, villages and airports from the map as objectives.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class DebugMarkers: Checkbox
            {
                property = "AIC_ModuleCommander_DebugMarkers";
                displayName = "Debug markers";
                tooltip = "Draw the general's view (objectives, threats, orders) on the map.";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class ReportToPlayers: Checkbox
            {
                property = "AIC_ModuleCommander_ReportToPlayers";
                displayName = "Report to players";
                tooltip = "Send short HQ situation reports to players of the commanded side.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class ManageDynSim: Checkbox
            {
                property = "AIC_ModuleCommander_ManageDynSim";
                displayName = "Manage dynamic simulation";
                tooltip = "Park idle garrisons with dynamic simulation (frozen while no player is near) and wake them when the general needs them or enemies come close. Lets the general run very large armies without lag. Groups with variable AIC_noDynSim = true are never touched.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class ManageGarrisons: Checkbox
            {
                property = "AIC_ModuleCommander_ManageGarrisons";
                displayName = "Manage garrisons";
                tooltip = "Distribute groups between owned objectives and bases: bases hold a reserve that refills towns whose garrison was sent elsewhere.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class UseTransport: Checkbox
            {
                property = "AIC_ModuleCommander_UseTransport";
                displayName = "Use transport";
                tooltip = "Infantry ordered far away get a ride in an idle truck, APC or helicopter.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class ManageCleanup: Checkbox
            {
                property = "AIC_ModuleCommander_ManageCleanup";
                displayName = "Manage cleanup";
                tooltip = "Delete empty groups, and bodies and wrecks of this side once they have been dead for 300 s with no player within 500 m (max 20 per cycle). Objects and groups with variable AIC_keep = true are never deleted.";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription
        {
            description = "Creates an AI general that commands every AI group of the chosen side. Sync 'AI Commander Objective' modules to add objectives. Sync a trigger to delay activation; deactivating the trigger removes the commander. Groups with variable AIC_exclude = true are ignored.";
            sync[] = {"AIC_ModuleObjective"};
            class AIC_ModuleObjective
            {
                description = "Objective the general will try to capture or hold.";
                side = 7;
                optional = 1;
                duplicate = 1;
                synced[] = {};
            };
        };
    };

    // ------------------------------------------------------------------
    // AI Commander Objective
    // ------------------------------------------------------------------
    class AIC_ModuleObjective: Module_F
    {
        scope = 2;
        scopeCurator = 0;
        displayName = "AI Commander Objective";
        category = "AIC_Modules";
        function = "AIC_fnc_moduleObjective";
        functionPriority = 1;      // before commander modules
        isGlobal = 0;
        isTriggerActivated = 0;
        isDisposable = 0;
        is3DEN = 0;

        class Attributes: AttributesBase
        {
            class Name: Edit
            {
                property = "AIC_ModuleObjective_Name";
                displayName = "Name";
                tooltip = "Objective name used in reports and markers. Empty = automatic.";
                typeName = "STRING";
                defaultValue = "''";
            };
            class Radius: Edit
            {
                property = "AIC_ModuleObjective_Radius";
                displayName = "Radius (m)";
                tooltip = "Capture / control radius around the module position.";
                typeName = "NUMBER";
                defaultValue = "300";
            };
            class Priority: Edit
            {
                property = "AIC_ModuleObjective_Priority";
                displayName = "Priority";
                tooltip = "Strategic value. 1 = village, 2 = city, 3 = capital. Higher values attract more forces.";
                typeName = "NUMBER";
                defaultValue = "2";
            };
            class Garrison: Edit
            {
                property = "AIC_ModuleObjective_Garrison";
                displayName = "Garrison power";
                tooltip = "Desired garrison power while the objective is held (about 1 per infantry soldier, 6 per APC, 10 per tank). 0 = automatic from priority.";
                typeName = "NUMBER";
                defaultValue = "0";
            };
            class IsBase: Checkbox
            {
                property = "AIC_ModuleObjective_IsBase";
                displayName = "Base / staging area";
                tooltip = "Base or staging area: only a small guard stays, every other group here is a reserve the general can send anywhere.";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class ModuleDescription: ModuleDescription {};
        };

        class ModuleDescription: ModuleDescription
        {
            description = "Marks a position as an objective for every AI Commander. The module position is the objective centre. Tick 'Base / staging area' to make it a reserve base whose groups reinforce other objectives.";
            position = 1;
        };
    };
};
