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
    // garrison men at their spots without pathfinding until engaged (AIC_fnc_garrisonPath)
    ["garrisonHoldPath", true],
    // m: parked squads this far from any player and enemy are stored as
    // data, their men come back at 0.75 x (AIC_fnc_cacheCycle); 0 = off
    ["cacheDistance", 2500],
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
    // every vehicle of a garrison gets a post of its own at the approaches
    // of the place (AIC_fnc_garrisonVehicles); off: the group holds one
    // road spot on the threatened side
    ["garrisonVehiclePosts", true],
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
    // helicopters land fast under fire and fast-rope squads in where they
    // cannot land (AIC_fnc_heliInsert); ACE3's fast rope when it is loaded
    ["heliHotLanding", true],
    ["useFastRope", true],
    ["fastRopeUseAce", true],
    ["useParadrop", true],
    ["paradropDistance", 3000],
    // squads fly between two held airfields when the trip is longer than
    // this (m) or crosses water (AIC_fnc_airliftFor)
    ["useAirlift", true],
    ["airliftDistance", 6000],
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
    ["useQRF", true],
    // a base keeps a quick-reaction force only while this many motorised /
    // mechanised groups are at home there: a lone APC joins the attacks instead
    ["qrfMinVehicleGroups", 2],
    // a broken group gathers a kilometre off, is picked up and taken home
    // (AIC_fnc_recoverCycle), and its dead are replaced at the base
    // (AIC_fnc_refillGroup): at most this many men per base an hour
    ["recoverBroken", true],
    ["replaceLosses", true],
    ["replaceLossesPerHour", 24],
    // the groups on overwatch fire on the defenders while the assault goes in
    // (AIC_fnc_suppressFor); the guns lay smoke on the near edge of the
    // objective as it starts and light a night fight for men without night
    // vision (AIC_fnc_supportCycle)
    ["suppressiveFire", true],
    ["useSmoke", true],
    ["useIllumination", true]
]
