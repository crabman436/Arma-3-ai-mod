/*
    Function: AIC_fnc_defaultSettings

    Description:
        Returns a fresh HashMap with the default commander settings
        (see CONTRACT.md, "Settings HashMap" and the logistics extension:
        dynamic simulation, garrisons and transport; garbage management;
        the Jev decision model; the realism extension: recon, morale,
        order delays, night assaults, quick-reaction forces;
        the replan-on-contact extension).

    Parameters:
        None

    Returns:
        HashMap - new settings HashMap (caller may modify it freely)

    Example:
        private _settings = [] call AIC_fnc_defaultSettings;
*/

createHashMapFromArray [
    ["loopInterval", 30],
    ["aggression", 0.5],
    ["retreatThreshold", 0.3],
    ["reserveRatio", 0.2],
    ["useArtillery", true],
    ["useAir", true],
    ["autoObjectives", true],
    ["objectiveRadius", 300],
    ["maxAutoObjectives", 12],
    ["excludePlayerGroups", true],
    // groups handed to connected headless clients (AIC_fnc_hcBalance)
    ["useHeadlessClients", true],
    ["debugMarkers", false],
    ["reportToPlayers", true],
    ["artyCooldown", 120],
    ["airCooldown", 180],
    ["casSkill", 0.8],

    // --- reaction: early cycles when groups meet the enemy
    ["replanOnContact", true],
    ["replanMinInterval", 10],

    // --- logistics: dynamic simulation
    ["manageDynSim", true],
    ["dynSimWakeRange", 1000],
    ["dynSimDistance", 0],

    // --- logistics: garrisons
    ["manageGarrisons", true],
    ["garrisonPerPriority", 8],
    ["garrisonMovesPerCycle", 2],
    ["garrisonManStatics", true],
    ["useVehicleParks", true],
    // --- logistics: digging in at held places (AIC_fnc_fortifyCycle)
    ["fortifyObjectives", true],
    ["fortifyRoadblocks", true],
    ["fortifyServicePoints", true],
    ["fortifyMaxObjects", 400],
    ["stagedAssaults", true],
    ["spreadGroups", true],

    // --- logistics: transport
    ["useTransport", true],
    ["splitPassengers", true],
    ["dynamicSquads", true],
    ["useSupplyTrucks", true],
    ["transportMinDistance", 1200],
    ["heliTransportDistance", 3000],
    ["useParadrop", true],
    ["paradropDistance", 3000],
    ["transportSearchRadius", 4000],

    // --- garbage management
    ["manageCleanup", true],
    ["cleanupDelay", 300],
    ["cleanupPlayerDistance", 500],
    ["cleanupMaxPerCycle", 20],

    // --- Jev decision model (CONTRACT.md, "Jev extension")
    ["jevEnabled", true],
    ["jevWeight", 0.6],
    ["jevMinConfidence", 0.3],
    ["jevInterval", 0],
    ["jevModel", "jev-latest"],
    ["jevMaxPerMinute", 30],

    // --- realism (CONTRACT.md, "Realism extension")
    ["useRecon", true],
    ["useMorale", true],
    ["orderDelay", 1.0],
    ["nightAssaults", true],
    ["useQRF", true]
]
