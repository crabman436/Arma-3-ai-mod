/*
    Function: AIC_fnc_defaultSettings

    Description:
        Returns a fresh HashMap with the default commander settings
        (see CONTRACT.md, "Settings HashMap" and the logistics extension:
        dynamic simulation, garrisons and transport; garbage management).

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
    ["debugMarkers", false],
    ["reportToPlayers", true],
    ["artyCooldown", 120],
    ["airCooldown", 180],

    // --- logistics: dynamic simulation
    ["manageDynSim", true],
    ["dynSimWakeRange", 1000],
    ["dynSimDistance", 0],

    // --- logistics: garrisons
    ["manageGarrisons", true],
    ["garrisonPerPriority", 5],
    ["garrisonMovesPerCycle", 2],
    ["garrisonManStatics", true],

    // --- logistics: transport
    ["useTransport", true],
    ["splitPassengers", true],
    ["transportMinDistance", 1200],
    ["heliTransportDistance", 3000],
    ["transportSearchRadius", 4000],

    // --- garbage management
    ["manageCleanup", true],
    ["cleanupDelay", 300],
    ["cleanupPlayerDistance", 500],
    ["cleanupMaxPerCycle", 20]
]
